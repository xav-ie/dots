# Transcribe audio/video files using faster-whisper (GPU accelerated)
def main [] {
  print "Usage: whisper-transcribe <command>"
  print ""
  print "Commands:"
  print "  file <path>     Transcribe an audio/video file"
  print "  stream          Live transcription from microphone"
  print "  list-tracks     List audio tracks in a video file"
  print ""
  print "Run 'whisper-transcribe <command> --help' for more info"
}

# Live transcription from microphone/audio input in real-time
def "main stream" [
  --model: string = "large-v3"                  # Whisper model (tiny, base, small, medium, large-v2, large-v3, turbo)
  --language: string = "en"                     # Language code (en, es, fr) or "auto" for detection
  --capture: int = -1                           # Audio capture device ID (-1 = default)
  --volume-threshold: float = 0.2               # Minimum volume to trigger transcription
  --device: string = "auto"                     # Compute device: auto, cpu, or cuda
  --compute-type: string = "auto"               # Quantization: auto, float16, int8, etc.
  --word-timestamps                             # Enable word-level timestamps
] {
  print $"Starting real-time transcription \(model: ($model), device: ($device)\)..."
  print "Press Ctrl+C to stop"

  mut args = [
    --model $model
    --device $device
    --compute_type $compute_type
    --live_transcribe true
    --live_volume_threshold $volume_threshold
  ]

  if $language != "auto" {
    $args = ($args | append [--language $language])
  }

  if $capture != -1 {
    $args = ($args | append [--live_input_device $capture])
  }

  if $word_timestamps {
    $args = ($args | append [--word_timestamps true])
  }

  whisper-ctranslate2 ...$args
}

# Transcribe an audio or video file to text (txt, srt, vtt, json, tsv)
def "main file" [
  file: path                                    # Audio or video file to transcribe
  --model: string = "large-v3"                  # Whisper model (tiny, base, small, medium, large-v2, large-v3, turbo)
  --language: string = "en"                     # Language code (en, es, fr) or "auto" for detection
  --output: string                              # Output file path (defaults to input with new extension)
  --format: string = "txt"                      # Output format (txt, srt, vtt, json, tsv)
  --extract-audio                               # Extract and save audio file (for video files)
  --audio-track: int = -1                       # Audio track number (0 = first, -1 = auto-select)
  --device: string = "auto"                     # Compute device: auto, cpu, or cuda
  --compute-type: string = "auto"               # Quantization: auto, float16, int8, etc.
  --vad                                         # Enable voice activity detection filter
  --batched                                     # Use batched transcription for 2-4x speedup
  --word-timestamps                             # Enable word-level timestamps
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

  # Determine output directory
  let output_dir = if ($output | is-empty) {
    $file_path | path dirname
  } else {
    $output | path dirname
  }

  # Check if we need to extract audio from video
  let video_extensions = [mp4 mkv avi mov wmv flv webm]
  let file_ext = $file_path | path parse | get extension | str downcase
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
        $audio_tracks | each { |t| print $"  ($t.display)" }
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
    let temp_audio = $"/tmp/whisper-temp-($file_path | path basename | str replace -a '/' '-').wav"
    print $"Extracting audio track ($selected_track) to temporary file..."
    bash -c $"ffmpeg -i '($file_path)' -map 0:a:($selected_track) -ar 16000 -ac 1 -c:a pcm_s16le '($temp_audio)' -y 2>&1 | grep -v '^frame='"
    print "Audio extraction completed"
    $temp_audio
  } else {
    $audio_file
  }

  mut args = [
    --model $model
    --device $device
    --compute_type $compute_type
    --output_dir $output_dir
    --output_format $format
  ]

  if $language != "auto" {
    $args = ($args | append [--language $language])
  }

  if $vad {
    $args = ($args | append [--vad_filter true])
  }

  if $batched {
    $args = ($args | append [--batched true])
  }

  if $word_timestamps {
    $args = ($args | append [--word_timestamps true])
  }

  $args = ($args | append [$final_audio])

  print $"Transcribing with faster-whisper \(model: ($model), device: ($device)\)..."
  whisper-ctranslate2 ...$args

  # Handle custom output path if specified
  if ($output | is-not-empty) {
    let default_output = $final_audio | path parse | update extension $format | path join
    if $default_output != $output and ($default_output | path exists) {
      mv $default_output $output
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
    if ($final_audio | str starts-with '/tmp/whisper-temp-') {
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
