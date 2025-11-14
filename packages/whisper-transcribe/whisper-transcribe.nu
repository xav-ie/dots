# Transcribe audio/video files using whisper.cpp
def main [
  file?: path                                   # Audio or video file to transcribe (optional when using --stream)
  --model: string = "base.en"                   # Whisper model to use (tiny, base, small, medium, large-v2, large-v3)
  --language: string = "en"                     # Language code (en, es, fr, etc.)
  --output: string                              # Output file path (optional, defaults to input file with new extension)
  --format: string = "text"                     # Output format (text, srt, vtt, json)
  --extract-audio                               # Extract and save audio file (useful for video files)
  --no-timestamps                               # Do not include timestamps in output
  --audio-track: int = -1                       # Audio track number to extract (0 = first, 1 = second, etc.; -1 = auto-select)
  --list-tracks                                 # List available audio tracks and exit
  --stream                                      # Stream mode: transcribe from microphone/audio input in real-time
  --capture: int = -1                           # Audio capture device ID (use -1 for default)
  --step: int = 3000                            # Audio step size in milliseconds (streaming mode)
  --length: int = 10000                         # Audio length in milliseconds (streaming mode)
  --keep: int = 200                             # Audio to keep from previous step in ms (streaming mode)
  --vad-thold: float = 0.6                      # Voice activity detection threshold (streaming mode)
  --save-audio                                  # Save recorded audio to file (streaming mode)
] {
  # Expand tilde if present in file path
  let file_path = if ($file | is-empty) {
    ""
  } else if ($file | str starts-with '~') {
    $file | str replace '~' $env.HOME
  } else {
    $file
  }

  # In streaming mode, file is optional
  if not $stream {
    if ($file_path | is-empty) {
      print "Error: File path is required when not in streaming mode"
      exit 1
    }

    if not ($file_path | path exists) {
      print $"Error: File '($file)' does not exist"
      exit 1
    }
  }

  # File-specific operations (skip in streaming mode)
  if not $stream {
    # List audio tracks if requested
    if $list_tracks {
      print "Available audio tracks:"
      let probe_result = ffprobe -v error -show_entries stream=index,codec_type,codec_name:stream_tags=language,title -of json $file_path
        | complete

      if $probe_result.exit_code != 0 {
        print $"Error: Failed to probe file: ($probe_result.stderr)"
        exit 1
      }

      let tracks = $probe_result.stdout
        | from json
        | get -o streams
        | default []
        | where codec_type == "audio"
        | enumerate

      if ($tracks | is-empty) {
        print "No audio tracks found"
        exit 0
      }

      $tracks | each { |track|
        let lang = $track.item.tags?.language? | default "unknown"
        let title = $track.item.tags?.title? | default ""
        let codec = $track.item.codec_name
        print $"  Track ($track.index): ($lang) - ($codec) ($title)"
      }
      exit 0
    }
  }

  # Determine output file (only for file-based mode)
  let output_file = if $stream {
    $output
  } else if ($output | is-empty) {
    $file_path | path parse | update extension $format | path join
  } else {
    $output
  }

  # Check if we need to extract audio from video (only for file-based mode)
  let video_extensions = [mp4 mkv avi mov wmv flv webm]
  let file_ext = if $stream { "" } else { $file_path | path parse | get extension | str downcase }
  let needs_extraction = if $stream { false } else { $file_ext in $video_extensions }

  # Determine which audio track to use
  let selected_track = if $needs_extraction {
    # Get all audio tracks
    let probe_result = ffprobe -v error -show_entries stream=index,codec_type,codec_name:stream_tags=language,title -of json $file_path
      | complete

    if $probe_result.exit_code != 0 {
      print $"Error: Failed to probe file: ($probe_result.stderr)"
      exit 1
    }

    let audio_tracks = $probe_result.stdout
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

    if ($audio_tracks | is-empty) {
      print "Error: No audio tracks found in video file"
      exit 1
    }

    # If user didn't specify track
    if $audio_track == -1 {
      # If multiple tracks, ask them to choose
      if ($audio_tracks | length) > 1 {
        print "Multiple audio tracks detected:"
        $audio_tracks | each { |t| print $"  ($t.display)" }
        let selection = input $"Select audio track \(0-($audio_tracks | length | $in - 1)\): "
        $selection | into int
      } else {
        # Only one track, use it
        0
      }
    } else {
      # User specified a track, use it
      $audio_track
    }
  } else {
    # For non-video files, default to track 0 if not specified
    if $audio_track == -1 { 0 } else { $audio_track }
  }

  # Determine if we should use streaming extraction or save to file
  let should_save_audio = $extract_audio or (not $needs_extraction)

  let audio_file = if $stream {
    # No audio file needed in streaming mode
    ""
  } else if $needs_extraction and $should_save_audio {
    # Only save audio file if explicitly requested
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
    # Stream extraction - will use process substitution
    ""
  } else {
    $file_path
  }

  # Download model if needed
  let model_dir = $"($env.HOME)/.cache/whisper-models"
  let model_path = $"($model_dir)/ggml-($model).bin"

  if not ($model_path | path exists) {
    print $"Model not found. Downloading ggml-($model)..."
    mkdir $model_dir
    let model_url = $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-($model).bin"

    if (which curl | is-not-empty) {
      curl -L $model_url -o $model_path
    } else if (which wget | is-not-empty) {
      wget $model_url -O $model_path
    } else {
      print "Error: Neither curl nor wget found. Cannot download model."
      exit 1
    }
  }

  # Run transcription - streaming or file-based
  if $stream {
    # Streaming mode using whisper-stream
    print $"Starting real-time transcription \(model: ($model)\)..."
    print "Press Ctrl+C to stop"

    mut stream_args = [
      -m $model_path
      -l $language
      --step $step
      --length $length
      --keep $keep
      --vad-thold $vad_thold
    ]

    # Add capture device if specified
    if $capture != -1 {
      $stream_args = ($stream_args | append [-c $capture])
    }

    # Add output file if specified
    if not ($output | is-empty) {
      $stream_args = ($stream_args | append [-f $output])
    }

    # Add save audio flag if requested
    if $save_audio {
      $stream_args = ($stream_args | append [--save-audio])
    }

    whisper-stream ...$stream_args
  } else {
    # File-based transcription using whisper-cli

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

    mut whisper_args = [
      -m $model_path
      -l $language
      -f $final_audio
    ]

    # Add format-specific arguments
    match $format {
      "text" => {
        if $no_timestamps {
          $whisper_args = ($whisper_args | append [-nt])
        }
        $whisper_args = ($whisper_args | append [-otxt])
      }
      "srt" => {
        $whisper_args = ($whisper_args | append [-osrt])
      }
      "vtt" => {
        $whisper_args = ($whisper_args | append [-ovtt])
      }
      "json" => {
        $whisper_args = ($whisper_args | append [-oj])
      }
      _ => {
        print $"Error: Unknown format '($format)'"
        exit 1
      }
    }

    # Run transcription
    print $"Transcribing with whisper.cpp \(model: ($model)\)..."
    whisper-cli ...$whisper_args

    # Move output to desired location if different
    let whisper_output = $final_audio | path parse | update extension $format | path join
    if $whisper_output != $output_file and ($whisper_output | path exists) {
      mv $whisper_output $output_file
    }

    print $"Transcription saved to: ($output_file)"

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
}
