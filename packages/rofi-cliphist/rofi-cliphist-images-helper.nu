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

# Generate the rofi menu entries (images only)
def generate_entries [temp_dir: string] {
  let full_list = (cliphist list | lines)

  # Set rofi options
  let null = (char --unicode "0000")
  let sep = (char --unicode "001f")
  print $"($null)prompt($sep)🖼️"
  print $"($null)markup-rows($sep)true"
  print $"($null)show-icons($sep)true"

  # Filter and generate entries for images only with larger thumbnails
  let image_entries = ($full_list | enumerate | where { |entry|
    let parts = ($entry.item | split column "\t" id text)
    let text = ($parts | get text | first)
    $text | str contains "[[ binary data"
  })

  $image_entries | enumerate | each { |item|
    let entry = $item.item
    let num = $item.index + 1
    let idx = $entry.index
    let line = $entry.item
    let parts = ($line | split column "\t" id text)
    let text = ($parts | get text | first)

    # Decode image to temp file for thumbnail
    let thumb_path = $"($temp_dir)/thumb_($idx).png"
    $line | cliphist decode | save -f $thumb_path

    # Display with number
    print $"($num)($null)icon($sep)($thumb_path)($sep)info($sep)($idx)"
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
