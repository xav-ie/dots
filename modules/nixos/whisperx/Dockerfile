# WhisperX transcription/diarization service image.
#
# Base brings torch 2.5.1 + CUDA 12.4 + cuDNN 9 already matched, so the pip
# install below neither downgrades torch to a CPU wheel nor mismatches the
# cuDNN that ctranslate2 (faster-whisper) links against. ffmpeg is required —
# whisperx.load_audio shells out to it to decode the opus/webm the extension
# uploads.
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Deps first so the (slow) pip layer caches across service-code edits. The
# constraints file pins the torch stack to the base image's matched CUDA wave so
# the whisperx resolve can't upgrade torch out from under torchvision.
COPY requirements.txt constraints.txt /app/
RUN pip install --no-cache-dir -c /app/constraints.txt -r /app/requirements.txt \
    # whisperx 3.4.2 caps ctranslate2<4.5 (cuDNN 8), but this base ships cuDNN 9
    # and ctranslate2 4.4's wheel bundles an incomplete cuDNN 8 (missing
    # libcudnn_ops_infer.so.8) → segfault on the first inference. 4.5+ targets
    # cuDNN 9, matching torch and the complete cuDNN-9 set in the image.
    # --no-deps overrides whisperx's cap without disturbing the resolved stack.
    && pip install --no-cache-dir --no-deps 'ctranslate2>=4.5,<5'

COPY transcribe_service.py /app/transcribe_service.py

# Put the torch nvidia-* wheels' cuDNN 9 + cuBLAS libs on the loader path so
# ctranslate2 can dlopen them (torch finds its own via RPATH, but ctranslate2
# searches the standard loader path).
ENV LD_LIBRARY_PATH=/opt/conda/lib/python3.11/site-packages/nvidia/cudnn/lib:/opt/conda/lib/python3.11/site-packages/nvidia/cublas/lib

# Model weights (faster-whisper, alignment, pyannote) land here; the Nix module
# bind-mounts a host dir over it so downloads persist across container restarts.
ENV HF_HOME=/cache/huggingface

EXPOSE 8000
CMD ["uvicorn", "transcribe_service:app", "--host", "0.0.0.0", "--port", "8000"]
