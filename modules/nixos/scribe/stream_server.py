"""Live streaming ASR over WebSocket — NVIDIA parakeet-unified, NeMo buffered RNNT.

A thin, single-purpose service: accept mono int16 PCM frames over a WebSocket
and stream back incrementally-decoded text with per-word timestamps. NO
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
                      16 kHz audio the model heard, <channel>.json its words
"""

import asyncio
import json
import logging
import math
import os
import re
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from omegaconf import OmegaConf, open_dict
from scipy.signal import resample_poly

import nemo.collections.asr as nemo_asr
from nemo.collections.asr.parts.submodules.rnnt_decoding import RNNTDecodingConfig
from nemo.collections.asr.parts.utils.streaming_utils import (
    ContextSize,
    StreamingBatchedAudioBuffer,
)
from nemo.utils import logging as nemo_logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

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
        cfg.fused_batch_size = -1
    model.change_decoding_strategy(cfg)
    model.preprocessor.featurizer.dither = 0.0
    model.preprocessor.featurizer.pad_to = 0
    model.eval()
    return model


model = _load_model()
decoding_computer = model.decoding.decoding.decoding_computer

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
                x=enc, out_len=dec_len, prev_batched_state=self.decoder_state
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

    def text(self):
        return " ".join(w["word"] for w in self.words)


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
                self.meta_path.write_text(json.dumps({**self.meta, "words": words}))


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

    async def send():
        await websocket.send_text(
            json.dumps({"type": "partial", "text": state.text(), "words": state.words})
        )

    try:
        while True:
            msg = await websocket.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("text"):
                config = json.loads(msg["text"])
                src_rate = int(config.get("sampleRate", SAMPLE_RATE))
                if recording is None:
                    recording = _open_recording(config, src_rate)
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
        if recording is not None:
            # Keep the tail shorter than one step too, so the file is complete.
            recording.close(state.words, _to_16k(state.pending, src_rate))
