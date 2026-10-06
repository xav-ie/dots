"""Live streaming ASR over WebSocket — NVIDIA parakeet-unified, NeMo buffered RNNT.

A thin, single-purpose service: accept mono int16 PCM frames over a WebSocket
and stream back incrementally-decoded words with timestamps. Each update is
{"type": "words", "from": i, "words": [...]}: replace the client's words from
index i on. Only the last word already sent can still change (a word split
across chunks), so an update never resends the rest of the transcript. NO
diarization — speaker attribution is done client-side in the extension by
joining these word timestamps against the meeting's active-speaker timeline.

The chunk loop follows NeMo's buffered streaming script
(examples/asr/asr_chunked_inference/rnnt/speech_to_text_streaming_infer_rnnt.py,
v3.0.0) at batch size 1: each step re-encodes left context + chunk + right
context and greedily decodes only the chunk, carrying the decoder state over.
Decoded tokens are never revised, so every word sent is final.

Tunables (set by the Nix module via env):
  SCRIBE_MODEL        HF model id (default nvidia/parakeet-unified-en-0.6b)
  SCRIBE_LEFT_S       left context seconds (default 5.6)
  SCRIBE_CHUNK_S      chunk seconds (default 0.56); a step runs every chunk
  SCRIBE_RIGHT_S      right context (lookahead) seconds (default 0.56)
  SCRIBE_TS_OFFSET_S  subtracted from word times (default 0.29): RNNT emits
                      each token a steady ~0.29 s after the word starts
  SCRIBE_RECORDINGS   where streams asking to be saved land (default
                      /cache/recordings): <sessionId>/<channel>.flac holds the
                      16 kHz audio the model heard, <channel>.json its words,
                      and session.json the extension's record posted at stop
  SCRIBE_VOCAB        the global boost list, edited in the UI (default
                      /cache/vocab.json)
  SCRIBE_BOOST_SCORE  per-token boost inside a phrase (default 1.0; 3.0 began
                      forcing names into ordinary words in testing)
  SCRIBE_BOOST_ALPHA  weight of the boost in decoding (default 1.0)

A stream's first text message is {"sampleRate", "sessionId", "channel", "save",
"boost"}; "boost" (participant names) is boosted along with the vocabulary.

GET / serves ui.html, a browser for those sessions over the /api routes, and
/mcp is an MCP server (streamable HTTP) for listing, reading and searching
meeting transcripts and editing the vocabulary.
"""

import asyncio
import ctypes
import gc
import json
import logging
import math
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from omegaconf import OmegaConf, open_dict
from scipy.signal import resample_poly

import nemo.collections.asr as nemo_asr
from nemo.collections.asr.parts.context_biasing.biasing_multi_model import (
    BiasingRequestItemConfig,
)
from nemo.collections.asr.parts.context_biasing.boosting_graph_batched import (
    BoostingTreeModelConfig,
)
from nemo.collections.asr.parts.submodules.rnnt_decoding import RNNTDecodingConfig
from nemo.collections.asr.parts.utils.streaming_utils import (
    ContextSize,
    StreamingBatchedAudioBuffer,
)
from nemo.utils import logging as nemo_logging
from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse
from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

# NeMo logs the full model config on load — pages of noise. Keep WARNING and up.
nemo_logging.set_verbosity(logging.WARNING)

# GPU-only service: fail loudly rather than silently crawl on CPU.
if not torch.cuda.is_available():
    raise RuntimeError(
        "scribe: no CUDA GPU visible to the container; refusing to run on CPU"
    )
print(f"[scribe] CUDA ready: {torch.cuda.get_device_name(0)}", flush=True)

SAMPLE_RATE = 16000
MODEL_ID = os.environ.get("SCRIBE_MODEL", "nvidia/parakeet-unified-en-0.6b")
LEFT_S = float(os.environ.get("SCRIBE_LEFT_S", "5.6"))
CHUNK_S = float(os.environ.get("SCRIBE_CHUNK_S", "0.56"))
RIGHT_S = float(os.environ.get("SCRIBE_RIGHT_S", "0.56"))
TS_OFFSET_S = float(os.environ.get("SCRIBE_TS_OFFSET_S", "0.29"))
# Phrase boosting (names, jargon): per-token bonus inside a phrase and its weight.
BOOST_SCORE = float(os.environ.get("SCRIBE_BOOST_SCORE", "1.0"))
BOOST_ALPHA = float(os.environ.get("SCRIBE_BOOST_ALPHA", "1.0"))
# The global boost list (product names, jargon, people), edited in the UI.
VOCAB = Path(os.environ.get("SCRIBE_VOCAB", "/cache/vocab.json"))
MAX_PHRASES = 2000
MAX_PHRASE_LEN = 100
RECORDINGS = Path(os.environ.get("SCRIBE_RECORDINGS", "/cache/recordings"))
# The session id becomes a directory name, so only accept a UUID.
SESSION_ID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

torch.set_grad_enabled(False)


def _load_model():
    # Cast to bf16 on the CPU before moving to the GPU, so the fp32 weights never
    # land there: loading fp32 on the GPU and casting afterwards leaves ~1.2 GB
    # stranded in PyTorch's cache on a card shared with other services.
    model = nemo_asr.models.ASRModel.from_pretrained(MODEL_ID, map_location="cpu")
    model.freeze()
    model = model.to(torch.bfloat16).cuda()
    torch.cuda.empty_cache()

    cfg = OmegaConf.structured(RNNTDecodingConfig())  # greedy_batch + label looping
    with open_dict(cfg):
        cfg.greedy.preserve_alignments = False
        # Each stream can boost its own phrases (a meeting's participant names).
        cfg.greedy.enable_per_stream_biasing = True
        # Boosting's PyTorch path loops on data, which CUDA-graph capture of the
        # decoder can't record.
        cfg.greedy.use_cuda_graph_decoder = False
        cfg.fused_batch_size = -1
    model.change_decoding_strategy(cfg)
    model.preprocessor.featurizer.dither = 0.0
    model.preprocessor.featurizer.pad_to = 0
    model.eval()
    return model


model = _load_model()
# Loading frees the CPU-side fp32 weights and checkpoint (~4 GB), but glibc keeps
# the freed heap mapped; hand it back to the OS.
gc.collect()
ctypes.CDLL("libc.so.6").malloc_trim(0)
decoding_computer = model.decoding.decoding.decoding_computer
# Boosting's Triton kernels compile at run time with a C compiler and
# /sbin/ldconfig, which the Nix image doesn't have; use the PyTorch path.
decoding_computer.biasing_multi_model.use_triton = False

_stride = model.cfg.preprocessor["window_stride"]
_sub = model.encoder.subsampling_factor
ENC_SAMPLES = (
    (int(SAMPLE_RATE * _stride) // _sub) * _sub * _sub
)  # samples per encoder frame
FRAME_S = ENC_SAMPLES / SAMPLE_RATE  # 0.08
_ctx_frames = ContextSize(
    left=int(LEFT_S / _stride / _sub),
    chunk=int(CHUNK_S / _stride / _sub),
    right=int(RIGHT_S / _stride / _sub),
)
CTX = ContextSize(
    left=_ctx_frames.left * ENC_SAMPLES,
    chunk=_ctx_frames.chunk * ENC_SAMPLES,
    right=_ctx_frames.right * ENC_SAMPLES,
)
if model.cfg.encoder.att_context_style == "chunked_limited_with_rc":
    model.encoder.set_default_att_context_size(
        att_context_size=[_ctx_frames.left, _ctx_frames.chunk, _ctx_frames.right]
    )

app = FastAPI()

# Serialize GPU calls — one model, one GPU. Each socket keeps its own state.
_gpu_lock = asyncio.Lock()


class StreamState:
    """All per-connection streaming state — buffers and decoder state must not be shared."""

    def __init__(self):
        self.buffer = StreamingBatchedAudioBuffer(
            batch_size=1, context_samples=CTX, dtype=torch.float32, device="cuda"
        )
        self.decoder_state = None
        self.pending = np.empty(
            0, dtype=np.float32
        )  # source-rate audio not yet decoded
        self.started = False  # the first step needs chunk + right context
        # Accumulated [{word,start,end}] plus the token ids of each word, so a word
        # split across chunks keeps growing until the next word starts.
        self.words: list[dict] = []
        self.word_ids: list[list[int]] = []
        self.boundary = False  # a bare ▁ token arrived: the next piece starts a word
        # This stream's boosting model in the decoder (-1: none).
        self.boost_id = -1
        self.boost_ids = torch.tensor([-1], device="cuda")

    def set_boost(self, phrases):
        """Boost these phrases for the rest of the stream. Blocking — via to_thread."""
        if self.boost_id >= 0 or not phrases:
            return
        request = BiasingRequestItemConfig(
            boosting_model_cfg=BoostingTreeModelConfig(
                key_phrases_list=phrases, context_score=BOOST_SCORE, use_triton=False
            ),
            boosting_model_alpha=BOOST_ALPHA,
        )
        request.add_to_multi_model(
            tokenizer=model.tokenizer,
            biasing_multi_model=decoding_computer.biasing_multi_model,
        )
        self.boost_id = request.multi_model_id
        self.boost_ids = torch.tensor([self.boost_id], device="cuda")

    def close(self):
        if self.boost_id >= 0:
            decoding_computer.biasing_multi_model.remove_model(self.boost_id)
            self.boost_id = -1

    def step_size(self):
        return CTX.chunk if self.started else CTX.chunk + CTX.right

    def step(self, audio_16k, last=False):
        """Decode one chunk. Blocking — call via to_thread."""
        n = audio_16k.shape[0]
        audio = torch.from_numpy(audio_16k).unsqueeze(0).cuda()
        last_b = torch.tensor([last], device="cuda")
        with torch.inference_mode():
            self.buffer.add_audio_batch_(
                audio,
                audio_lengths=torch.tensor([n], device="cuda"),
                is_last_chunk=last,
                is_last_chunk_batch=last_b,
            )
            enc, enc_len = model(
                input_signal=self.buffer.samples,
                input_signal_length=self.buffer.context_size_batch.total(),
            )
            enc = enc.transpose(1, 2)
            ec = self.buffer.context_size.subsample(factor=ENC_SAMPLES)
            ecb = self.buffer.context_size_batch.subsample(factor=ENC_SAMPLES)
            enc = enc[:, ec.left :]
            dec_len = torch.where(last_b, enc_len - ecb.left, ecb.chunk)
            hyps, self.decoder_state = decoding_computer(
                x=enc,
                out_len=dec_len,
                prev_batched_state=self.decoder_state,
                multi_biasing_ids=self.boost_ids,
            )
            k = int(hyps.current_lengths[0])
            ids = hyps.transcript[0, :k].tolist()
            frames = hyps.timestamps[0, :k].tolist()
        self._add_tokens(ids, frames)
        self.started = True

    def _add_tokens(self, ids, frames):
        # Token timestamps are encoder frames from stream start. SentencePiece marks
        # a word's first piece with ▁; a bare ▁ is a lone boundary before the next piece.
        for tid, f in zip(ids, frames):
            t = f * FRAME_S
            piece = model.tokenizer.ids_to_tokens([tid])[0]
            if piece == "▁":
                self.boundary = True
                continue
            if piece.startswith("▁") or self.boundary or not self.words:
                self.boundary = False
                self.word_ids.append([tid])
                self.words.append(
                    {
                        "word": "",
                        "start": round(max(0.0, t - TS_OFFSET_S), 2),
                        "end": 0.0,
                    }
                )
            else:
                self.word_ids[-1].append(tid)
            self.words[-1]["word"] = model.tokenizer.ids_to_text(
                self.word_ids[-1]
            ).strip()
            self.words[-1]["end"] = round(max(0.0, t + FRAME_S - TS_OFFSET_S), 2)


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": MODEL_ID,
        "left_s": LEFT_S,
        "chunk_s": CHUNK_S,
        "right_s": RIGHT_S,
        "ts_offset_s": TS_OFFSET_S,
    }


class Recording:
    """One saved stream: the 16 kHz audio fed to the model plus, on close, its words.

    A channel reopened within a session (the mic toggled off and on) gets a
    numbered stem, so earlier streams are kept.
    """

    def __init__(self, session_id, channel, src_rate):
        folder = RECORDINGS / session_id
        folder.mkdir(parents=True, exist_ok=True)
        stem, n = channel, 1
        while (folder / f"{stem}.json").exists() or (folder / f"{stem}.flac").exists():
            n += 1
            stem = f"{channel}-{n}"
        self.audio_path = folder / f"{stem}.flac"
        self.meta_path = folder / f"{stem}.json"
        self.meta = {
            "sessionId": session_id,
            "channel": channel,
            "sourceSampleRate": src_rate,
            "startedAt": datetime.now(timezone.utc).isoformat(),
            "model": MODEL_ID,
        }
        self.audio = sf.SoundFile(
            self.audio_path,
            "w",
            samplerate=SAMPLE_RATE,
            channels=1,
            format="FLAC",
            subtype="PCM_16",
        )

    def close(self, words, tail):
        # Each step runs even if an earlier one fails, so a write error (disk
        # full) still closes the file and keeps the words.
        try:
            self.audio.write(tail)
        finally:
            try:
                self.audio.close()
            finally:
                # A stream that closed before any audio leaves an unreadable
                # zero-frame FLAC; keep only the metadata.
                if self.audio.frames == 0:
                    self.audio_path.unlink(missing_ok=True)
                _write_json(self.meta_path, {**self.meta, "words": words})


def _write_json(path, data):
    # Readers (the session browser) never see a half-written file.
    tmp = path.with_name(f"{path.name}.{uuid.uuid4().hex}.tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(path)


def _read_json(path):
    """None when missing or unreadable, so one bad file can't break a listing."""
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        return None


def _to_16k(audio, src_rate):
    if src_rate == SAMPLE_RATE:
        return audio
    g = math.gcd(src_rate, SAMPLE_RATE)
    return resample_poly(audio, SAMPLE_RATE // g, src_rate // g).astype(np.float32)


def _open_recording(config, src_rate):
    session_id, channel = config.get("sessionId"), config.get("channel")
    if (
        not config.get("save")
        or not SESSION_ID_RE.fullmatch(str(session_id))
        or channel not in ("tab", "mic")
    ):
        return None
    return Recording(session_id, channel, src_rate)


# --- session browser ---------------------------------------------------------

UI_HTML = (Path(__file__).parent / "ui.html").read_text()
STEM_RE = re.compile(r"^(tab|mic)(-[0-9]+)?$")
MAX_SESSION_BYTES = 50 * 2**20


def _clean_phrases(items):
    """Strings only, trimmed, bounded, deduplicated in order."""
    out = {}
    for item in items if isinstance(items, list) else []:
        if (
            isinstance(item, str)
            and (p := " ".join(item.split()))
            and len(p) <= MAX_PHRASE_LEN
        ):
            out.setdefault(p, None)
    return list(out)[:MAX_PHRASES]


def _boost_phrases(names):
    """The vocabulary plus a meeting's participant names, and their first names,
    which is how people are usually addressed."""
    names = _clean_phrases(names)
    firsts = [n.split()[0] for n in names if len(n.split()) > 1]
    return _clean_phrases((_read_json(VOCAB) or []) + names + firsts)


def _session_dir(session_id):
    if not SESSION_ID_RE.fullmatch(session_id):
        raise HTTPException(404)
    return RECORDINGS / session_id


def _channels(folder, with_words):
    """Saved streams in a session. A stream still being recorded has audio but no
    metadata yet, and its FLAC header isn't final."""
    stems = {p.stem for p in folder.glob("*.flac")} | {
        p.stem for p in folder.glob("*.json") if STEM_RE.fullmatch(p.stem)
    }
    out = []
    for stem in sorted(stems):
        meta_path, audio_path = folder / f"{stem}.json", folder / f"{stem}.flac"
        meta = _read_json(meta_path) or {}
        if not with_words:
            meta.pop("words", None)
        try:
            duration = sf.info(audio_path).duration if audio_path.exists() else 0.0
        except RuntimeError:
            duration = None
        out.append(
            {**meta, "stem": stem, "audio": audio_path.exists(), "duration": duration}
        )
    return out


def _read_session(folder):
    return _read_json(folder / "session.json")


# The browser routes are plain `def`, so FastAPI runs their file work in its
# threadpool instead of on the event loop serving live /ws streams.
@app.get("/", response_class=HTMLResponse)
def ui():
    return UI_HTML


@app.get("/api/sessions")
def list_sessions():
    if not RECORDINGS.exists():
        return []
    out = []
    for folder in RECORDINGS.iterdir():
        if not folder.is_dir() or not SESSION_ID_RE.fullmatch(folder.name):
            continue
        session = _read_session(folder) or {}
        segments = session.get("segments") or []
        out.append(
            {
                "sessionId": folder.name,
                "startedAt": session.get("startedAt"),
                "stoppedAt": session.get("stoppedAt"),
                "platform": session.get("platform"),
                "speakers": sorted({s["speaker"] for s in segments}),
                "words": sum(len(s["text"].split()) for s in segments),
                "channels": _channels(folder, with_words=False),
                "hasRecord": bool(session),
                "modified": folder.stat().st_mtime,
            }
        )
    return sorted(
        out, key=lambda s: s["startedAt"] or s["modified"] * 1000, reverse=True
    )


@app.get("/api/sessions/{session_id}")
def get_session(session_id: str):
    folder = _session_dir(session_id)
    if not folder.is_dir():
        raise HTTPException(404)
    return {
        "sessionId": session_id,
        "session": _read_session(folder),
        "channels": _channels(folder, with_words=True),
    }


@app.post("/api/sessions/{session_id}")
async def put_session(session_id: str, request: Request):
    """The extension's record of a finished recording: transcript, speaker
    timeline, per-stream words and clocks, adapter snapshots."""
    folder = _session_dir(session_id)
    body = await request.body()
    if len(body) > MAX_SESSION_BYTES:
        raise HTTPException(413)
    try:
        record = json.loads(body)
    except ValueError:
        raise HTTPException(400) from None
    if not isinstance(record, dict):
        raise HTTPException(400)

    def save():
        folder.mkdir(parents=True, exist_ok=True)
        _write_json(folder / "session.json", record)

    await asyncio.to_thread(save)
    return {"ok": True}


@app.get("/api/vocab")
def get_vocab():
    return {"phrases": _read_json(VOCAB) or []}


@app.put("/api/vocab")
async def put_vocab(request: Request):
    try:
        body = json.loads(await request.body())
    except ValueError:
        raise HTTPException(400) from None
    phrases = _clean_phrases(body.get("phrases") if isinstance(body, dict) else None)
    await asyncio.to_thread(_write_json, VOCAB, phrases)
    return {"phrases": phrases}


@app.get("/api/sessions/{session_id}/audio/{stem}")
def get_audio(session_id: str, stem: str):
    path = _session_dir(session_id) / f"{stem}.flac"
    if not STEM_RE.fullmatch(stem) or not path.exists():
        raise HTTPException(404)
    return FileResponse(path, media_type="audio/flac")


@app.websocket("/ws")
async def ws(websocket: WebSocket):
    await websocket.accept()
    state = StreamState()
    recording = None

    # The extension's AudioContext is usually 48 kHz; a text message
    # {"sampleRate": N, "sessionId", "channel", "save"} (sent first) sets the
    # source rate, resampled to 16 kHz here, and whether to keep the audio.
    # Binary messages are raw int16-LE mono PCM.
    src_rate = SAMPLE_RATE

    sent = 0  # words the client has; the last of them may still grow
    connected = True

    async def send():
        nonlocal sent, connected
        if not connected:
            return
        start = max(0, sent - 1)
        sent = len(state.words)
        try:
            await websocket.send_text(
                json.dumps(
                    {"type": "words", "from": start, "words": state.words[start:]}
                )
            )
        except Exception:  # client gone: keep transcribing what it already sent
            connected = False

    # A client may send audio faster than real time (a recorded file). Take every
    # message off the socket as soon as it arrives, so the connection's own
    # traffic (keepalive pongs) is never stuck behind audio still waiting to be
    # transcribed, and work through the backlog from this queue. Audio received
    # before a disconnect is still transcribed (and saved).
    inbox = asyncio.Queue()

    async def read():
        try:
            while True:
                msg = await websocket.receive()
                await inbox.put(msg)
                if msg.get("type") == "websocket.disconnect":
                    return
        finally:
            # However the reader ends, the worker sees the end of the stream and
            # finishes up (saves the recording) instead of waiting forever.
            inbox.put_nowait({"type": "websocket.disconnect"})

    reader = asyncio.create_task(read())
    try:
        while True:
            msg = await inbox.get()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("text"):
                config = json.loads(msg["text"])
                if "sampleRate" in config:
                    src_rate = int(config["sampleRate"])
                    if recording is None:
                        recording = _open_recording(config, src_rate)
                    phrases = _boost_phrases(config.get("boost"))
                    if phrases:
                        async with _gpu_lock:
                            await asyncio.to_thread(state.set_boost, phrases)
                    if recording is not None:
                        recording.meta["boost"] = phrases
                # Wall-clock ms of the stream's first sample, sent once audio starts.
                if recording is not None and "epoch" in config:
                    recording.meta["epoch"] = config["epoch"]
                continue
            raw = msg.get("bytes")
            if not raw:
                continue
            chunk = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
            state.pending = np.concatenate([state.pending, chunk])
            # Resample one whole step at a time (not each small message), so
            # filter edge effects land only on step boundaries.
            while state.pending.shape[0] >= (
                size := round(state.step_size() * src_rate / SAMPLE_RATE)
            ):
                seg, state.pending = state.pending[:size], state.pending[size:]
                seg = _to_16k(seg, src_rate)
                if recording is not None:
                    recording.audio.write(seg)
                async with _gpu_lock:
                    await asyncio.to_thread(state.step, seg)
                await send()
    except WebSocketDisconnect:
        pass
    finally:
        reader.cancel()
        async with _gpu_lock:
            await asyncio.to_thread(state.close)
        if recording is not None:
            # Keep the tail shorter than one step too, so the file is complete.
            recording.close(state.words, _to_16k(state.pending, src_rate))


# --- MCP ---------------------------------------------------------------------

mcp = MCPServer(
    "scribe",
    instructions=(
        "Transcripts of meetings recorded by the meeting capture extension. "
        "Times are UTC. Speakers come from the meeting's active-speaker "
        "indicator; 'Unknown' is speech it couldn't attribute."
    ),
)


def _iso(ms):
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat() if ms else None


def _epoch_ms(iso):
    t = datetime.fromisoformat(iso)
    return (t if t.tzinfo else t.replace(tzinfo=timezone.utc)).timestamp() * 1000


def _sessions_between(since, until):
    lo = _epoch_ms(since) if since else -math.inf
    hi = _epoch_ms(until) if until else math.inf
    return [s for s in list_sessions() if s["startedAt"] and lo <= s["startedAt"] <= hi]


def _clock(sec):
    return f"{int(sec // 60)}:{int(sec % 60):02d}"


@mcp.tool()
def list_meetings(
    since: str | None = None, until: str | None = None, limit: int = 20
) -> list[dict]:
    """Recorded meetings, newest first. since/until are ISO 8601 times bounding
    when a meeting started (UTC when no offset is given)."""
    return [
        {
            "sessionId": s["sessionId"],
            "startedAt": _iso(s["startedAt"]),
            "stoppedAt": _iso(s["stoppedAt"]),
            "platform": s["platform"],
            "speakers": s["speakers"],
            "words": s["words"],
        }
        for s in _sessions_between(since, until)[:limit]
    ]


@mcp.tool()
def get_transcript(session_id: str) -> str:
    """A meeting's transcript as "[m:ss] Speaker: text" lines, m:ss from the
    start of the recording."""
    session = _read_session(_session_dir(session_id))
    if not session:
        raise ValueError(f"no transcript for session {session_id}")
    head = f"Meeting {session_id}, started {_iso(session.get('startedAt'))}, on {session.get('platform')}"
    lines = [
        f"[{_clock(s['start'])}] {s['speaker']}: {s['text']}"
        for s in session.get("segments") or []
    ]
    return "\n".join([head, "", *lines])


@mcp.tool()
def search_transcripts(
    query: str, since: str | None = None, until: str | None = None, limit: int = 50
) -> list[dict]:
    """Case-insensitive text search across meeting transcripts, newest meeting
    first. Each hit has the meeting, when in it, who spoke, and the text
    around the match."""
    needle = query.lower().strip()
    if not needle:
        raise ValueError("query is empty")
    hits = []
    for s in _sessions_between(since, until):
        session = _read_session(RECORDINGS / s["sessionId"]) or {}
        for seg in session.get("segments") or []:
            text = seg["text"]
            at = text.lower().find(needle)
            if at < 0:
                continue
            hits.append(
                {
                    "sessionId": s["sessionId"],
                    "startedAt": _iso(s["startedAt"]),
                    "at": _clock(seg["start"]),
                    "speaker": seg["speaker"],
                    "text": text[max(0, at - 300) : at + len(needle) + 300],
                }
            )
            if len(hits) >= limit:
                return hits
    return hits


@mcp.tool()
def get_vocab() -> list[str]:
    """Phrases (names, companies, terms) boosted in every meeting's recognition."""
    return _read_json(VOCAB) or []


@mcp.tool()
def add_vocab(phrases: list[str]) -> list[str]:
    """Add phrases to the boost list and return the whole list. Boost proper
    nouns the recognizer gets wrong; common words can hurt recognition."""
    vocab = _clean_phrases((_read_json(VOCAB) or []) + phrases)
    _write_json(VOCAB, vocab)
    return vocab


# Served at /mcp. Mounted last so every route above takes precedence. Host
# checks are off like the rest of the API; access is limited to the tailnet.
_mcp_app = mcp.streamable_http_app(
    stateless_http=True,
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)
app.router.lifespan_context = _mcp_app.router.lifespan_context
app.mount("", _mcp_app)
