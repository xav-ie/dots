"""Live streaming ASR over WebSocket — NVIDIA NeMo cache-aware FastConformer.

A thin, single-purpose service: accept 16 kHz mono PCM frames over a WebSocket
and stream back incrementally-decoded text with per-word timestamps. NO
diarization — speaker attribution is done client-side in the extension by
joining these word timestamps against the meeting's active-speaker timeline.

The cache-aware streaming loop (preprocessor config, pre-encode feature cache,
conformer_stream_step threading) follows NVIDIA's official live-mic demo:
tutorials/asr/Online_ASR_Microphone_Demo_Cache_Aware_Streaming.ipynb.

Tunables (set by the Nix module via env):
  SCRIBE_MODEL        HF model id (default the streaming-multi FastConformer)
  SCRIBE_LOOKAHEAD_MS one of {0,80,480,1040}; ~= algorithmic latency (default 480)
  SCRIBE_DECODER      rnnt | ctc (default rnnt; rnnt is more accurate)
"""

import asyncio
import copy
import json
import logging
import math
import os

import numpy as np
import torch
from omegaconf import OmegaConf, open_dict
from scipy.signal import resample_poly

import nemo.collections.asr as nemo_asr
from nemo.collections.asr.models import EncDecCTCModelBPE
from nemo.utils import logging as nemo_logging
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

# NeMo logs the full decoding config + train/val/test configs at INFO on model
# load — pages of noise. Keep WARNING and up. (lhotse's SyntaxWarnings are
# silenced separately via PYTHONWARNINGS in the Nix module, since they fire at
# import time before any code here runs.)
nemo_logging.set_verbosity(logging.WARNING)

# GPU-only service: fail loudly rather than silently crawl on CPU. (The NGC
# entrypoint's "Failed to detect NVIDIA driver version" banner is a cosmetic
# /proc read that the nvidia-container-toolkit CDI doesn't satisfy on NixOS — the
# CUDA driver itself is injected fine, which this check confirms positively.)
if not torch.cuda.is_available():
    raise RuntimeError("scribe: no CUDA GPU visible to the container; refusing to run on CPU")
print(f"[scribe] CUDA ready: {torch.cuda.get_device_name(0)}", flush=True)

SAMPLE_RATE = 16000
# FastConformer: 10 ms feature window stride * 8x subsampling = 80 ms per encoder
# output frame. This is the unit for both chunk sizing and timestamp conversion.
ENCODER_STEP_LENGTH_MS = 80

MODEL_ID = os.environ.get("SCRIBE_MODEL", "nvidia/stt_en_fastconformer_hybrid_large_streaming_multi")
LOOKAHEAD_MS = int(os.environ.get("SCRIBE_LOOKAHEAD_MS", "480"))
DECODER = os.environ.get("SCRIBE_DECODER", "rnnt")

# Per-step audio chunk: lookahead + one encoder frame. The trailing -1 matches
# NVIDIA's PyAudio frames_per_buffer in the reference demo.
CHUNK_SAMPLES = int(SAMPLE_RATE * (LOOKAHEAD_MS + ENCODER_STEP_LENGTH_MS) / 1000) - 1

app = FastAPI()

# Serialize GPU calls — one model, one GPU; concurrent conformer_stream_step
# calls from multiple sockets would race on CUDA. Single-user workload, so a
# lock is plenty (each socket still keeps its own streaming state).
_gpu_lock = asyncio.Lock()


def _load_model():
    # Generic loader resolves the concrete class for both the FastConformer
    # hybrid model and nemotron-speech-streaming.
    model = nemo_asr.models.ASRModel.from_pretrained(MODEL_ID)

    # Right-context = lookahead / frame; left context kept at the model default.
    if LOOKAHEAD_MS not in (0, 80, 480, 1040):
        raise ValueError(f"SCRIBE_LOOKAHEAD_MS must be one of 0/80/480/1040, got {LOOKAHEAD_MS}")
    try:
        left = model.encoder.att_context_size[0]
        model.encoder.set_default_att_context_size([left, LOOKAHEAD_MS // ENCODER_STEP_LENGTH_MS])
    except (AttributeError, TypeError):
        # Streaming-trained models without multi-lookahead — config is baked in.
        pass

    # Hybrid RNNT/CTC models (FastConformer-streaming-multi) need a head selected
    # via decoder_type; pure-RNNT models (nemotron-speech-streaming) don't accept
    # that kwarg and raise TypeError — fall through, they're RNNT already.
    try:
        model.change_decoding_strategy(decoder_type=DECODER)
    except TypeError:
        pass
    decoding_cfg = model.cfg.decoding
    with open_dict(decoding_cfg):
        decoding_cfg.strategy = "greedy"
        decoding_cfg.preserve_alignments = False
        # Leave NeMo's own timestamp computation OFF: on the streaming RNNT path
        # compute_rnnt_timestamps raises a char_offsets/processed_tokens length
        # mismatch mid-stream. We don't need it — the greedy decoder still fills
        # hyp.timestamp with per-token frame indices, which _word_timestamps()
        # groups into words itself.
        decoding_cfg.compute_timestamps = False
        if DECODER == "rnnt" and hasattr(model, "joint"):
            decoding_cfg.greedy.max_symbols = 10
            decoding_cfg.fused_batch_size = -1
    model.change_decoding_strategy(decoding_cfg)

    model.eval()
    return model


def _build_preprocessor(model):
    # Streaming-specific preprocessor: no dither, no padding, and crucially
    # normalize="None" — these models are trained with no input normalization,
    # so each chunk is preprocessed independently (no cross-chunk feature stats).
    cfg = copy.deepcopy(model._cfg)
    OmegaConf.set_struct(cfg.preprocessor, False)
    cfg.preprocessor.dither = 0.0
    cfg.preprocessor.pad_to = 0
    cfg.preprocessor.normalize = "None"
    pp = EncDecCTCModelBPE.from_config_dict(cfg.preprocessor)
    pp.to(model.device)
    return pp


asr_model = _load_model()
preprocessor = _build_preprocessor(asr_model)
PRE_ENCODE_CACHE = asr_model.encoder.streaming_cfg.pre_encode_cache_size[1]
N_MELS = asr_model.cfg.preprocessor.features


class StreamState:
    """All per-connection streaming state — caches must not be shared."""

    def __init__(self):
        (self.cache_last_channel,
         self.cache_last_time,
         self.cache_last_channel_len) = asr_model.encoder.get_initial_cache_state(batch_size=1)
        # Small slice of the previous chunk's mel features, prepended each step
        # to supply left context (zero-padded on the first chunk).
        self.pre_encode = torch.zeros((1, N_MELS, PRE_ENCODE_CACHE), device=asr_model.device)
        self.previous_hypotheses = None
        self.pred_out_stream = None
        # Total raw audio samples consumed → the stream clock for word stamping.
        self.processed_samples = 0
        # Accumulated [{word,start,end}] with stable timestamps, grown per chunk.
        self.stamped: list[dict] = []


def _stamp_words(state, text, t0, t1):
    """Assign timestamps to words by the chunk window that first decoded them.

    NeMo's per-token timestamps are unreliable on the streaming RNNT path, but we
    know each chunk's exact audio time span. Words are stable once decoded, so we
    keep the timestamps of the unchanged prefix and stamp newly-appeared words
    with this chunk's [t0, t1]. Chunk-grained (~0.5s) — ample for speaker
    attribution, which the active-speaker signal only resolves to ~0.5s anyway.
    """
    words = text.split()
    keep = 0
    while keep < len(state.stamped) and keep < len(words) and state.stamped[keep]["word"] == words[keep]:
        keep += 1
    state.stamped = state.stamped[:keep]
    for word in words[keep:]:
        state.stamped.append({"word": word, "start": round(t0, 2), "end": round(t1, 2)})
    return state.stamped


def _step(state, audio_16k):
    """Run one cache-aware streaming step. Blocking — call via to_thread."""
    sig = torch.from_numpy(audio_16k).unsqueeze(0).to(asr_model.device)
    slen = torch.tensor([audio_16k.shape[0]], device=asr_model.device)
    processed, processed_len = preprocessor(input_signal=sig, length=slen)

    processed = torch.cat([state.pre_encode, processed], dim=-1)
    processed_len = processed_len + state.pre_encode.shape[-1]
    state.pre_encode = processed[:, :, -PRE_ENCODE_CACHE:]

    with torch.no_grad():
        (state.pred_out_stream,
         transcribed,
         state.cache_last_channel,
         state.cache_last_time,
         state.cache_last_channel_len,
         state.previous_hypotheses) = asr_model.conformer_stream_step(
            processed_signal=processed,
            processed_signal_length=processed_len,
            cache_last_channel=state.cache_last_channel,
            cache_last_time=state.cache_last_time,
            cache_last_channel_len=state.cache_last_channel_len,
            keep_all_outputs=False,
            previous_hypotheses=state.previous_hypotheses,
            previous_pred_out=state.pred_out_stream,
            drop_extra_pre_encoded=None,
            return_transcription=True,
        )

    hyp = state.previous_hypotheses[0] if state.previous_hypotheses else None
    if hyp is not None and hyp.text is not None:
        text = hyp.text
    elif transcribed:
        text = transcribed[0]
    else:
        text = ""

    # This chunk's audio time window (raw samples in, not the feature cache).
    t0 = state.processed_samples / SAMPLE_RATE
    state.processed_samples += audio_16k.shape[0]
    t1 = state.processed_samples / SAMPLE_RATE
    return text.strip(), _stamp_words(state, text.strip(), t0, t1)


@app.get("/health")
async def health():
    return {"status": "ok", "model": MODEL_ID, "lookahead_ms": LOOKAHEAD_MS, "decoder": DECODER}


@app.websocket("/ws")
async def ws(websocket: WebSocket):
    await websocket.accept()
    state = StreamState()

    # The extension's AudioContext is usually 48 kHz; a text message
    # {"sampleRate": N} (sent any time, typically first) sets the source rate and
    # we resample to 16 kHz here. Binary messages are raw int16-LE mono PCM.
    src_rate = SAMPLE_RATE
    src_chunk = CHUNK_SAMPLES  # source-rate samples per 16 kHz model chunk
    buf = np.empty(0, dtype=np.float32)
    try:
        while True:
            msg = await websocket.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("text"):
                src_rate = int(json.loads(msg["text"]).get("sampleRate", SAMPLE_RATE))
                src_chunk = int(round(CHUNK_SAMPLES * src_rate / SAMPLE_RATE))
                continue
            raw = msg.get("bytes")
            if not raw:
                continue
            chunk = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
            buf = np.concatenate([buf, chunk])
            while buf.shape[0] >= src_chunk:
                seg, buf = buf[:src_chunk], buf[src_chunk:]
                if src_rate != SAMPLE_RATE:
                    g = math.gcd(src_rate, SAMPLE_RATE)
                    seg = resample_poly(seg, SAMPLE_RATE // g, src_rate // g).astype(np.float32)
                async with _gpu_lock:
                    text, words = await asyncio.to_thread(_step, state, seg)
                await websocket.send_text(json.dumps({"type": "partial", "text": text, "words": words}))
    except WebSocketDisconnect:
        pass
