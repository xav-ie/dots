{ writeShellApplication, wf-recorder }:
writeShellApplication {
  name = "record";
  runtimeInputs = [ wf-recorder ];
  text = ''
    # I am not sure if I should always record with audio or not
    sleep 2 && wf-recorder --  -r 60 -c libsvtav1 -C aac -f recording.mp4 $@
  '';
}
