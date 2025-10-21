def main [
  --images  # Show only images with larger previews
] {
  if $images {
    # Launch rofi in script mode for images only with larger icon size and height limit
    rofi -modi "images:rofi-cliphist-images-helper" -show images -theme-str "element-icon { size: 256px; } window { height: 90%; }"
  } else {
    # Launch rofi in script mode for all clipboard items
    rofi -modi "clipboard:rofi-cliphist-helper" -show clipboard
  }
}
