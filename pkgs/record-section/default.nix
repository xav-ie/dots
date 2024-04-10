{ writeShellApplication, slurp, wf-recorder }:
writeShellApplication {
  name = "record-section";
  runtimeInputs = [ slurp wf-recorder ];
  text = ''
    sleep 2 && wf-recorder --  -r 60 -c libsvtav1 -C aac -f recording.mp4 -g "$(slurp)" "$@"
  '';
}
