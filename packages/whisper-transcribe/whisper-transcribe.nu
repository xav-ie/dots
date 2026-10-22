# Transcribe audio/video files using whisper.cpp (GPU accelerated when the
# whisper-cpp package is built with CUDA — see modules/home/base.nix, which
# overrides it with the pkgs-bleeding-cuda build on Linux)
def main [] {
  print "Usage: whisper-transcribe <command>"
  print ""
  print "Commands:"
  print "  file <path>     Transcribe an audio/video file"
  print "  stream          Live transcription from microphone"
  print "  list-tracks     List audio tracks in a video file"
  print ""
  print "  list-devices    List available audio capture devices"
  print ""
  print "Run 'whisper-transcribe <command> --help' for more info"
}

# Resolve (downloading once into ~/.cache/whisper-models if needed) the path to
# a ggml model. Any name from https://huggingface.co/ggerganov/whisper.cpp
# works: tiny, base, small, medium, large-v3, large-v3-turbo, and quantized
# suffixes like large-v3-turbo-q8_0.
def ensure_model [model: string]: nothing -> string {
  let dir = $env.HOME | path join ".cache" "whisper-models"
  let path = $dir | path join $"ggml-($model).bin"
  if not ($path | path exists) {
    mkdir $dir
    let url = $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-($model).bin"
    print $"Downloading ($url) \(one-time, cached in ($dir))..."
    let tmp = $"($path).part"
    curl -L --fail -C - --progress-bar -o $tmp $url
    mv -f $tmp $path
  }
  $path
}

# The Silero VAD model whisper.cpp needs for --vad.
def ensure_vad_model []: nothing -> string {
  let dir = $env.HOME | path join ".cache" "whisper-models"
  let path = $dir | path join "ggml-silero-v5.1.2.bin"
  if not ($path | path exists) {
    mkdir $dir
    let url = "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin"
    print $"Downloading ($url) \(one-time, cached in ($dir))..."
    let tmp = $"($path).part"
    curl -L --fail -C - --progress-bar -o $tmp $url
    mv -f $tmp $path
  }
  $path
}

# List available audio capture devices and their IDs (for use with
# `stream --capture`)
def "main list-devices" [] {
  python3 -m sounddevice
}

# Live transcription from microphone/audio input in real-time
def "main stream" [
  --model: string = "large-v3"                  # Whisper model (tiny, base, small, medium, large-v3, large-v3-turbo, or a quantized variant like large-v3-turbo-q8_0)
  --language: string = "en"                     # Language code (en, es, fr) or "auto" for detection
  --capture: int = -1                           # Audio capture device ID (-1 = default, see list-devices)
  --step: int = 3000                            # Audio step size in milliseconds
  --length: int = 10000                         # Audio length in milliseconds
  --vad-threshold: float = 0.6                  # Voice activity detection threshold (0-1; only transcribes when speech is detected)
  --output: string                              # Live transcript output file
  --save-audio                                  # Save the recorded audio to a file
  --device: string = "auto"                     # Compute device: auto (GPU if available) or cpu
] {
  let model_path = (ensure_model $model)

  print $"Starting real-time transcription \(model: ($model), device: ($device))..."
  print "Press Ctrl+C to stop"

  mut args = [
    --model
    $model_path
    --language
    $language
    --step
    $step
    --length
    $length
    --vad-thold
    $vad_threshold
  ]

  if $capture != -1 {
    $args = ($args | append [--capture $capture])
  }

  if ($output | is-not-empty) {
    $args = ($args | append [--file $output])
  }

  if $save_audio {
    $args = ($args | append [--save-audio])
  }

  if $device == "cpu" {
    $args = ($args | append [--no-gpu])
  }

  whisper-stream ...$args
}

# Transcribe an audio or video file to text (txt, srt, vtt, json, csv)
def "main file" [
  file: path                                    # Audio or video file to transcribe
  --model: string = "large-v3"                  # Whisper model (tiny, base, small, medium, large-v3, large-v3-turbo, or a quantized variant like large-v3-turbo-q8_0)
  --language: string = "en"                     # Language code (en, es, fr) or "auto" for detection
  --output: string                              # Output file path (defaults to input with new extension)
  --format: string = "txt"                      # Output format (txt, srt, vtt, json, csv)
  --extract-audio                               # Extract and save audio file (for video files)
  --audio-track: int = -1                       # Audio track number (0 = first, -1 = auto-select)
  --device: string = "auto"                     # Compute device: auto (GPU if available) or cpu
  --vad                                         # Enable voice activity detection filter
  --no-timestamps                               # Do not print timestamps
] {
  # Expand tilde if present
  let file_path = if ($file | str starts-with '~') {
    $file | str replace '~' $env.HOME
  } else {
    $file
  }

  if not ($file_path | path exists) {
    print $"Error: File '($file)' does not exist"
    exit 1
  }

  # whisper.cpp writes CSV ("tsv" in the faster-whisper days); accept either name
  let format = if $format == "tsv" { "csv" } else { $format }
  let format_flag = {
    txt: "--output-txt"
    srt: "--output-srt"
    vtt: "--output-vtt"
    json: "--output-json"
    csv: "--output-csv"
  } | get $format

  let model_path = (ensure_model $model)

  # Determine output directory (default to current dir if no directory component)
  let output_dir = if ($output | is-empty) {
    let dir = $file_path | path dirname
    if ($dir | is-empty) { "." } else { $dir }
  } else {
    let dir = $output | path dirname
    if ($dir | is-empty) { "." } else { $dir }
  }

  # Check if we need to extract audio from video
  let video_extensions = [
    mp4
    mkv
    avi
    mov
    wmv
    flv
    webm
  ]
  let file_ext = $file_path | path parse | get extension | str lowercase
  let needs_extraction = $file_ext in $video_extensions

  # Determine which audio track to use
  let selected_track = if $needs_extraction {
    let audio_tracks = get_audio_tracks $file_path

    if ($audio_tracks | is-empty) {
      print "Error: No audio tracks found in video file"
      exit 1
    }

    if $audio_track == -1 {
      if ($audio_tracks | length) > 1 {
        print "Multiple audio tracks detected:"
        $audio_tracks | each {|t| print $"  ($t.display)" }
        let selection = input $"Select audio track \(0-($audio_tracks | length | $in - 1)\): "
        $selection | into int
      } else {
        0
      }
    } else {
      $audio_track
    }
  } else {
    if $audio_track == -1 { 0 } else { $audio_track }
  }

  # Determine if we should save extracted audio
  let should_save_audio = $extract_audio or (not $needs_extraction)

  let audio_file = if $needs_extraction and $should_save_audio {
    let audio_path = $file_path | path parse | update extension "wav" | path join
    print $"Extracting audio track ($selected_track) to ($audio_path)..."
    ffmpeg -i $file_path -map $"0:a:($selected_track)" -ar 16000 -ac 1 -c:a pcm_s16le $audio_path -y
    | complete
    | get stderr
    | lines
    | where { $in !~ "^frame=" }
    | str join "\n"
    | print
    print "Audio extraction completed"
    $audio_path
  } else if $needs_extraction {
    ""
  } else {
    $file_path
  }

  # If we need extraction but didn't save audio, use a temporary file
  let final_audio = if $needs_extraction and ($audio_file | is-empty) {
    let temp_audio = (mktemp -t whisper-XXXX --suffix .wav)
    print $"Extracting audio track ($selected_track) to temporary file..."
    ffmpeg -i $file_path -map $"0:a:($selected_track)" -ar 16000 -ac 1 -c:a pcm_s16le $temp_audio -y
    | complete
    | get stderr
    | lines
    | where { $in !~ "^frame=" }
    | str join "\n"
    | print
    print "Audio extraction completed"
    $temp_audio
  } else {
    $audio_file
  }

  # whisper-cli's -of takes a path WITHOUT extension and appends the format's
  # own extension (.txt, .srt, ...). Point it at the desired output base.
  let outbase = if ($output | is-not-empty) {
    let p = $output | path parse
    $p.parent | path join $p.stem
  } else {
    let p = $file_path | path parse
    $p.parent | path join $p.stem
  }

  mut args = [
    --model
    $model_path
    --file
    $final_audio
    --language
    $language
    --output-file
    $outbase
    $format_flag
  ]

  if $vad {
    $args = ($args | append [
      --vad
      --vad-model
      (ensure_vad_model)
    ])
  }

  if $no_timestamps {
    $args = ($args | append [--no-timestamps])
  }

  if $device == "cpu" {
    $args = ($args | append [--no-gpu])
  }

  print $"Transcribing with whisper.cpp \(model: ($model), device: ($device))..."
  whisper-cli ...$args

  # Handle custom output path if specified
  if ($output | is-not-empty) {
    let written = $"($outbase).($format)"
    if $written != $output and ($written | path exists) {
      mv $written $output
      print $"Transcription saved to: ($output)"
    }
  } else {
    let output_file = $file_path | path parse | update extension $format | path join
    print $"Transcription saved to: ($output_file)"
  }

  # Cleanup temporary audio files
  if $needs_extraction and (not $extract_audio) {
    if ($audio_file | is-not-empty) and ($audio_file != $file_path) {
      rm -f $audio_file
    }
    if ($final_audio != $file_path) and ($final_audio | str ends-with '.wav') {
      rm -f $final_audio
    }
  }
}

# List available audio tracks in a video file (useful for multi-language videos)
def "main list-tracks" [
  file: path                                    # Video file to inspect
] {
  let file_path = if ($file | str starts-with '~') {
    $file | str replace '~' $env.HOME
  } else {
    $file
  }

  if not ($file_path | path exists) {
    print $"Error: File '($file)' does not exist"
    exit 1
  }

  print "Available audio tracks:"
  let tracks = get_audio_tracks $file_path

  if ($tracks | is-empty) {
    print "No audio tracks found"
    exit 0
  }

  $tracks | each { |track|
    print $"  ($track.display)"
  }
}

# Extract audio track metadata from a video file using ffprobe
def get_audio_tracks [file_path: string] {
  let probe_result = ffprobe -v error -show_entries stream=index,codec_type,codec_name:stream_tags=language,title -of json $file_path
  | complete

  if $probe_result.exit_code != 0 {
    print $"Error: Failed to probe file: ($probe_result.stderr)"
    exit 1
  }

  $probe_result.stdout
  | from json
  | get -o streams
  | default []
  | where codec_type == "audio"
  | enumerate
  | each { |track|
        let lang = $track.item.tags?.language? | default "unknown"
        let title = $track.item.tags?.title? | default ""
        let codec = $track.item.codec_name
        {
          index: $track.index,
          lang: $lang,
          codec: $codec,
          title: $title,
          display: $"Track ($track.index): ($lang) - ($codec) ($title)"
        }
      }
}
