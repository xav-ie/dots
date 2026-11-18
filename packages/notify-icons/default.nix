{
  librsvg,
  runCommand,
}:
# Avatars for `notify --icon <name>`: claude, claude-praesidium (Claude asking
# from praesidium), morning, evening. Rendered to PNG for macOS's INImage and
# the Linux notification center alike.
runCommand "notify-icons" { nativeBuildInputs = [ librsvg ]; } ''
  mkdir -p $out
  for svg in ${./.}/*.svg; do
    name=$(basename "$svg" .svg)
    rsvg-convert -w 256 -h 256 "$svg" -o "$out/$name.png"
  done
''
