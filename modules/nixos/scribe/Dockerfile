# Runtime-built image (see build-scribe-image.service in scribe.nix, which
# mirrors the whisperx precedent). The exact python env stays pinned by
# pyproject.toml + uv.lock — the one validated by ~/Projects/asr-evals
# (NeMo 3.0.0, torch 2.14.0) — but the ~3.9 GiB of CUDA wheels lives only in
# podman's store instead of the system closure.
FROM python:3.12-slim

# soundfile dlopens libsndfile; ca-certificates for the HF model download.
# The CUDA stack ships inside the torch/nvidia-* wheels themselves, so a slim
# (non-CUDA) base + the CDI-injected driver is all that's needed.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsndfile1 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml uv.lock ./
# [tool.uv] package = false → only the pinned dependencies are installed.
RUN pip install --no-cache-dir uv \
 && uv sync --frozen --no-dev
COPY stream_server.py ui.html ./

ENV PATH="/app/.venv/bin:$PATH" \
    HOME=/tmp
EXPOSE 8000
CMD ["uvicorn", "stream_server:app", "--host", "0.0.0.0", "--port", "8000"]
