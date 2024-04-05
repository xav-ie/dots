{ writeShellApplication, slurp, wf-recorder }:
writeShellApplication {
  name = "record-section";
  runtimeInputs = [ slurp wf-recorder ];
  text = ''
    # the strange encoding is for firefox
    sleep 2 && wf-recorder -c libvpx-vp9 -f recording.mp4 -g "$(slurp)"
  '';
}
