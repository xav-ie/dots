# Handle selection and copy to clipboard
def handle_selection [temp_dir: string] {
  let rofi_info = ($env.ROFI_INFO? | default "")

  if not ($rofi_info | is-empty) {
    let full_list = (cliphist list | lines)
    let selected_line = ($full_list | get ($rofi_info | into int))
    $selected_line | cliphist decode | wl-copy
  }

  # Clean up temp directory
  rm -rf $temp_dir
}

# Generate the rofi menu entries
def generate_entries [temp_dir: string] {
  let full_list = (cliphist list | lines)

  # Set rofi options
  let null = (char --unicode "0000")
  let sep = (char --unicode "001f")
  print $"($null)prompt($sep)📋"
  print $"($null)markup-rows($sep)true"
  print $"($null)show-icons($sep)true"

  # Generate entries with thumbnails for images
  $full_list | enumerate | each { |entry|
    let idx = $entry.index
    let line = $entry.item
    let parts = ($line | split column "\t" id text)
    let text = ($parts | get text | first)

    # Check if this is an image based on cliphist's metadata
    let is_image = ($text | str contains "[[ binary data")

    # Format the output with icon if it's an image
    if $is_image {
      # Decode image to temp file for thumbnail
      let thumb_path = $"($temp_dir)/thumb_($idx).png"
      $line | cliphist decode | save -f $thumb_path

      # Escape any special characters in text for markup
      let display_text = ($text | str replace -a "&" "&amp;" | str replace -a "<" "&lt;" | str replace -a ">" "&gt;")
      print $"($display_text)($null)icon($sep)($thumb_path)($sep)info($sep)($idx)"
    } else {
      # Text entry - just show the text
      print $"($text)($null)info($sep)($idx)"
    }
  }

  return
}

def main [
  selection?: string  # The selected text (passed by rofi, but we use ROFI_INFO instead)
] {
  # Create temp directory for image thumbnails
  let temp_dir = (mktemp -d)

  # Get rofi state from environment
  let rofi_retv = ($env.ROFI_RETV? | default "0")

  # User selected or cancelled
  if $rofi_retv != "0" {
    handle_selection $temp_dir
    exit 0
  }

  # Initial call from rofi - generate the list
  generate_entries $temp_dir
}
