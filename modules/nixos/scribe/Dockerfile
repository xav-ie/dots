# Live streaming ASR service image.
#
# FROM the official NVIDIA NeMo container so torch / CUDA / cuDNN / numba and the
# whole NeMo ASR stack are pinned-and-matched by NVIDIA — the bleeding-edge
# streaming models (FastConformer streaming-multi, nemotron-speech-streaming)
# are only supported on this runtime. We add just the web layer on top. Pulling
# this base needs an NGC login (handled by the build oneshot in the Nix module).
FROM nvcr.io/nvidia/nemo:26.02

# ffmpeg: the NeMo image omits it, so pydub (pulled in by NeMo) warns at import.
# We send raw PCM (no decoding), but installing it silences the warning and
# covers any NeMo audio path that shells out to it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Web layer only — everything ML-related is already in the base.
RUN pip install --no-cache-dir \
    "fastapi==0.115.6" "uvicorn[standard]==0.34.0" "websockets==14.1"

COPY stream_server.py /app/stream_server.py
WORKDIR /app

# Model checkpoints (FastConformer/nemotron from HF) cache here; the Nix module
# bind-mounts a host dir over it so they persist across container restarts.
ENV HF_HOME=/cache/huggingface
ENV NEMO_CACHE_DIR=/cache/nemo

EXPOSE 8000
# Clear the NGC entrypoint wrapper so uvicorn runs directly. That wrapper only
# prints the copyright/MOTD banner and probes the driver version via a /proc read
# the CDI doesn't expose on NixOS ("Failed to detect NVIDIA driver version") — it
# does no CUDA setup (that's the container-toolkit hook + image env), so dropping
# it just removes the noisy/misleading banner. The CUDA assert in stream_server.py
# guards against any regression.
ENTRYPOINT []
CMD ["uvicorn", "stream_server:app", "--host", "0.0.0.0", "--port", "8000"]
