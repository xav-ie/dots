# whisper-transcribe

Transcribe audio and video files using [whisper.cpp](https://github.com/ggml-org/whisper.cpp) — a high-performance C++ implementation of OpenAI's Whisper — via a `nu` CLI. On Linux the underlying `whisper-cpp` is built with CUDA (see `modules/home/base.nix`, which overrides it with the `pkgs-bleeding-cuda` build), so transcription and streaming run on the GPU.

## Commands

```bash
whisper-transcribe file <path> [options]    # Transcribe an audio/video file
whisper-transcribe stream [options]         # Live transcription from microphone
whisper-transcribe list-tracks <file>       # List audio tracks in a video
whisper-transcribe list-devices             # List audio capture devices (for stream --capture)
```

Run `whisper-transcribe <command> --help` for the full flag list.

## `file`

```bash
whisper-transcribe file video.mp4                        # → video.txt next to the input
whisper-transcribe file podcast.mp3 --format srt         # subtitles
whisper-transcribe file movie.mkv --audio-track 1        # pick a dub directly
whisper-transcribe file lecture.wav --vad                # skip non-speech segments
whisper-transcribe file meeting.mp3 --device cpu         # force CPU
```

| Flag | Default | Notes |
| --- | --- | --- |
| `--model` | `large-v3` | Any ggml model name (see below) |
| `--language` | `en` | Language code, or `auto` to detect |
| `--output` | input path | Output file (extension sets the format unless `--format` given) |
| `--format` | `txt` | `txt`, `srt`, `vtt`, `json`, `csv` (`tsv` accepted as alias) |
| `--extract-audio` | off | Keep the extracted audio for video inputs |
| `--audio-track` | `-1` | Track number; `-1` prompts when a video has multiple tracks |
| `--vad` | off | Silero voice-activity filter (model auto-downloaded) |
| `--device` | `auto` | `auto` (GPU if available) or `cpu` |
| `--no-timestamps` | off | Plain text without `[start -> end]` markers |

## `stream`

```bash
whisper-transcribe stream                                # default microphone, live text
whisper-transcribe stream --model large-v3-turbo         # faster model
whisper-transcribe stream --capture 2                    # specific device (see list-devices)
whisper-transcribe stream --step 0 --length 30000        # sliding window; only transcribes speech
whisper-transcribe stream --output live.txt --save-audio # transcript + recording
```

| Flag | Default | Notes |
| --- | --- | --- |
| `--model` | `large-v3` | |
| `--language` | `en` | |
| `--capture` | `-1` | Capture device ID, `-1` = system default |
| `--step` | `3000` | Audio step size in ms |
| `--length` | `10000` | Audio window length in ms |
| `--vad-threshold` | `0.6` | Speech detection threshold (0–1) |
| `--output` | — | Live transcript output file |
| `--save-audio` | off | Save the recorded audio |
| `--device` | `auto` | `auto` or `cpu` |

## Models

Models are downloaded once from [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) into `~/.cache/whisper-models/` (as `ggml-<name>.bin`). Any name from that repo works, including quantized variants:

| Model | Parameters | VRAM | Speed | Accuracy |
| --- | --- | --- | --- | --- |
| `tiny` / `tiny.en` | 39M | ~1 GB | ~32x | Lower |
| `base` / `base.en` | 74M | ~1 GB | ~16x | Good |
| `small` | 244M | ~2 GB | ~6x | Better |
| `medium` | 769M | ~5 GB | ~2x | Great |
| `large-v3` (default) | 1550M | ~10 GB | 1x | Best |
| `large-v3-turbo` | 809M | ~6 GB | ~8x | Near `large-v3` |
| `large-v3-turbo-q8_0` | 809M | ~3 GB | ~8x | Near `large-v3`, quantized |

`--vad` additionally downloads the Silero VAD model (`ggml-silero-v5.1.2.bin`, from `ggml-org/whisper-vad`) into the same cache.

## Notes

- **Video input**: audio is extracted with ffmpeg to a temp file (16 kHz mono wav) and cleaned up afterwards; `--extract-audio` keeps it. Multi-track videos prompt for a track unless `--audio-track` is given.
- **Output files** land next to the input by default, named after the input stem (`video.srt`); `--output` overrides path and name.
- **CUDA** comes from the `pkgs-bleeding-cuda` whisper-cpp build wired up in `modules/home/base.nix` — the same store path `hyprwhspr` uses, so there is no second copy in the closure.

## Troubleshooting

- **Out of memory**: use a smaller or quantized model, e.g. `--model large-v3-turbo-q8_0`.
- **No speech in output**: try `--vad` (skips silence/music), and verify the language with `--language auto`.
- **Wrong capture device**: `whisper-transcribe list-devices`, then `stream --capture <id>`.
- **Manual model download**: fetch `ggml-<model>.bin` from the HuggingFace repo above into `~/.cache/whisper-models/`.
