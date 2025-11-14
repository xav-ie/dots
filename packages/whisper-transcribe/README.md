# whisper-transcribe

Transcribe audio and video files using [whisper.cpp](https://github.com/ggml-org/whisper.cpp) - a high-performance C++ implementation of OpenAI's Whisper.

## Features

- **High-performance C++ implementation** - Much faster than Python implementations
- **CUDA acceleration** built-in for GPU processing
- **Low memory usage** - See model memory requirements below
- **Real-time streaming** from microphone with voice activity detection (VAD)
- Automatic audio extraction from video files (uses temporary files, auto-cleaned)
- Multiple output formats: text, SRT, VTT, JSON
- Multiple Whisper model sizes (tiny to large-v3-turbo)
- Automatic model downloading from HuggingFace
- Automatic language detection

## Usage

### Basic transcription

```bash
# Transcribe a video file (automatically extracts audio)
whisper-transcribe video.mp4

# Transcribe an audio file
whisper-transcribe audio.wav

# Real-time transcription from microphone
whisper-transcribe --stream
```

### Options

```bash
whisper-transcribe [file] [OPTIONS]

File-based transcription options:
  <file>                   Audio or video file to transcribe (optional when using --stream)
  --output <PATH>          Output file path (default: input with new extension)
  --format <FORMAT>        Output format (default: text)
                          Options: text, srt, vtt, json
  --extract-audio          Keep extracted audio file (for videos)
  --no-timestamps          Omit timestamps from text output
  --audio-track <N>        Select audio track number (0 = first, 1 = second, etc.)
                          If not specified and multiple tracks exist, you'll be prompted
  --list-tracks            List available audio tracks and exit

Streaming mode options:
  --stream                 Enable real-time transcription from microphone
  --capture <ID>           Audio capture device ID (default: -1 for default device)
  --step <MS>              Audio step size in milliseconds (default: 3000)
  --length <MS>            Audio length in milliseconds (default: 10000)
  --keep <MS>              Audio to keep from previous step (default: 200)
  --vad-thold <N>          Voice activity detection threshold 0-1 (default: 0.6)
  --save-audio             Save recorded audio to file

Common options:
  --model <MODEL>          Whisper model size (default: base.en)
                          Options: tiny, base, small, medium, large-v2, large-v3
  --language <LANG>        Language code (default: en)
                          Examples: en, es, fr, de, ja, zh
```

### Examples

#### File-based transcription

```bash
# Use smaller model for faster processing
whisper-transcribe video.mp4 --model base

# Generate SRT subtitles
whisper-transcribe video.mp4 --format srt

# Transcribe Spanish audio
whisper-transcribe podcast.mp3 --language es

# Custom output path
whisper-transcribe video.mp4 --output transcript.txt

# Text without timestamps
whisper-transcribe lecture.mp4 --no-timestamps

# List available audio tracks
whisper-transcribe video.mkv --list-tracks

# Automatically prompts for track selection if multiple tracks exist
whisper-transcribe video.mkv
# Multiple audio tracks detected:
#   Track 0: rus - ac3 RUS Dub 2.0
#   Track 1: eng - ac3 ENG 5.1
# Select audio track (0-1): _

# Or specify track directly (no prompt)
whisper-transcribe video.mkv --audio-track 1
```

#### Real-time streaming transcription

```bash
# Basic streaming from default microphone
whisper-transcribe --stream

# Stream with a specific model
whisper-transcribe --stream --model base

# Stream with custom step and length (faster response, less context)
whisper-transcribe --stream --step 500 --length 5000

# Sliding window mode with VAD (set step to 0)
# Only transcribes when speech is detected
whisper-transcribe --stream --step 0 --length 30000 --vad-thold 0.6

# Stream and save output to a file
whisper-transcribe --stream --output live-transcript.txt

# Stream and save the recorded audio
whisper-transcribe --stream --save-audio

# Stream from a specific capture device
whisper-transcribe --stream --capture 0

# Stream Spanish audio
whisper-transcribe --stream --language es
```

## Output Formats

### Text (default)

```
[0.00s -> 5.23s] Hello, this is a test transcription.
[5.23s -> 10.45s] It includes timestamps for each segment.
```

### SRT (SubRip subtitles)

```
1
00:00:00,000 --> 00:00:05,230
Hello, this is a test transcription.

2
00:00:05,230 --> 00:00:10,450
It includes timestamps for each segment.
```

### VTT (WebVTT subtitles)

```
WEBVTT

00:00:00,000 --> 00:00:05,230
Hello, this is a test transcription.

00:00:05,230 --> 00:00:10,450
It includes timestamps for each segment.
```

### JSON (one object per line)

```json
{"start": 0.0, "end": 5.23, "text": "Hello, this is a test transcription."}
{"start": 5.23, "end": 10.45, "text": "It includes timestamps for each segment."}
```

## Model Sizes

| Model    | Parameters | VRAM  | Speed | Accuracy |
| -------- | ---------- | ----- | ----- | -------- |
| tiny     | 39M        | ~1GB  | ~32x  | Lower    |
| base     | 74M        | ~1GB  | ~16x  | Good     |
| small    | 244M       | ~2GB  | ~6x   | Better   |
| medium   | 769M       | ~5GB  | ~2x   | Great    |
| large-v2 | 1550M      | ~10GB | 1x    | Best     |
| large-v3 | 1550M      | ~10GB | 1x    | Best     |

**Recommendation**: Use `base` for quick testing, `large-v2` or `large-v3` for production.

## Technical Details

This package uses:

- **whisper.cpp**: High-performance C/C++ implementation of Whisper
- **CUDA acceleration**: Built-in GPU support (NVIDIA)
- **FFmpeg**: For audio extraction from video files
- **Automatic model management**: Downloads models from HuggingFace on first use

Models are cached in `~/.cache/whisper-models/` and only downloaded once.

### Audio Extraction

When transcribing video files:

- Audio is extracted to a temporary file in `/tmp`
- The temporary file is automatically cleaned up after transcription
- Use `--extract-audio` to keep the extracted audio file instead

For real-time microphone transcription, use the `--stream` flag which captures and transcribes audio continuously.

## Troubleshooting

### Out of memory

If transcription fails with OOM errors, try a smaller model:

```bash
whisper-transcribe video.mp4 --model small
```

### Unsupported video format

If FFmpeg can't extract audio, convert the video first:

```bash
ffmpeg -i input.webm -c:a copy output.mp4
whisper-transcribe output.mp4
```

### Model download fails

If automatic model download fails, you can manually download models from:

```
https://huggingface.co/ggerganov/whisper.cpp/tree/main
```

Place them in `~/.cache/whisper-models/` with names like `ggml-base.en.bin`.
