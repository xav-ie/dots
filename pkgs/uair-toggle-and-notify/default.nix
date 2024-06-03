{ writeShellApplication
, uair
, notify
,
}:
writeShellApplication {
  name = "uair-toggle-and-notify";
  runtimeInputs = [
    uair
    notify
  ];
  text = ''
    toggle_success=$(uairctl toggle || echo "false")
    if [[ "$toggle_success" != "false" ]]; then 
      notify "$(uairctl fetch "{state}")"
    else
      nohup uair > /dev/null 2>&1 &
      disown
      sleep 1
      if uairctl toggle; then
        notify "Starting new session..."
      fi
    fi
  '';
}
