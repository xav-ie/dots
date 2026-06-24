"""WhisperX transcription + diarization HTTP service.

A thin single-purpose FastAPI app: accept an audio POST, run the WhisperX
pipeline (transcribe -> align -> diarize), return speaker-labelled segments.
Models load once at startup, not per request — the first boot blocks while the
faster-whisper, alignment and pyannote weights download into HF_HOME.

Tunables come from the environment (set by the Nix module):
  WHISPERX_MODEL    faster-whisper model size       (default large-v3)
  WHISPERX_DEVICE   cuda | cpu                       (default cuda)
  WHISPERX_COMPUTE  float16 | int8 | ...             (default float16)
  WHISPERX_BATCH    transcribe batch size            (default 16)
  HF_TOKEN          required — pyannote model gating  (no default)
"""

import os
import tempfile

import whisperx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# The diarization pipeline moved into the `whisperx.diarize` submodule in
# recent releases (older code imported `whisperx.DiarizationPipeline`). Pinned
# to whisperx==3.4.2 in requirements.txt, which exposes it here.
from whisperx.diarize import DiarizationPipeline

DEVICE = os.environ.get("WHISPERX_DEVICE", "cuda")
COMPUTE = os.environ.get("WHISPERX_COMPUTE", "float16")
MODEL_SIZE = os.environ.get("WHISPERX_MODEL", "large-v3")
BATCH_SIZE = int(os.environ.get("WHISPERX_BATCH", "16"))
HF_TOKEN = os.environ["HF_TOKEN"]  # KeyError at startup if unset — fail loud.

app = FastAPI()

# The extension's offscreen document POSTs cross-origin from a chrome-extension://
# page. Wide-open here; the service only listens on the local/Tailscale net and
# Traefik fronts it. Tighten allow_origins to the stable extension id later.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["*"],
)

# --- load models once at startup ---
asr_model = whisperx.load_model(MODEL_SIZE, DEVICE, compute_type=COMPUTE)
diarize_model = DiarizationPipeline(use_auth_token=HF_TOKEN, device=DEVICE)

# Alignment models are language-specific; cache them lazily as languages appear.
_align_cache: dict = {}


def _get_align_model(lang: str):
    if lang not in _align_cache:
        _align_cache[lang] = whisperx.load_align_model(language_code=lang, device=DEVICE)
    return _align_cache[lang]


@app.get("/health")
async def health():
    # Only returns 200 once the models above have loaded — uvicorn doesn't
    # accept connections until module import (and thus model load) completes.
    return {"status": "ok", "model": MODEL_SIZE, "device": DEVICE}


@app.post("/transcribe")
async def transcribe(request: Request):
    raw = await request.body()
    with tempfile.NamedTemporaryFile(suffix=".webm", delete=True) as f:
        f.write(raw)
        f.flush()

        audio = whisperx.load_audio(f.name)  # ffmpeg decodes opus/webm
        result = asr_model.transcribe(audio, batch_size=BATCH_SIZE)

        model_a, metadata = _get_align_model(result["language"])
        result = whisperx.align(
            result["segments"],
            model_a,
            metadata,
            audio,
            DEVICE,
            return_char_alignments=False,
        )

        diarize_segments = diarize_model(audio)
        result = whisperx.assign_word_speakers(diarize_segments, result)

    segments = [
        {
            "speaker": seg.get("speaker", "UNKNOWN"),
            "start": seg["start"],
            "end": seg["end"],
            "text": seg["text"].strip(),
        }
        for seg in result["segments"]
    ]
    return JSONResponse({"language": result.get("language"), "segments": segments})
