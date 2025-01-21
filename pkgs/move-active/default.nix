{
  writeText,
  writeShellApplication,
  jq,
  nushell,
  hyprland,
  stdenv,
}:
# TODO: use https://github.com/shanyouli/nur-packages/blob/4365127bfdb0b97919c71d6763d9b9ea2c4d178f/nix/plib/nuenv.nix#L64
writeShellApplication {
  name = "move-active";
  runtimeInputs = [
    jq
    nushell
    hyprland
  ];

  # disable shellcheck
  checkPhase = ''
    runHook preCheck
    ${stdenv.shellDryRun} "$target"
    runHook postCheck
  '';

  text =
    let
      # TODO: format properly
      nuScript =
        writeText "move-active.nu" # nu
          ''
            const waybar_height = 34

            export def windowInfo [] {
              let border_size = (hyprctl getoption general:border_size -j | jq .int) | from json
              let gaps = (hyprctl getoption general:gaps_out -j
                          | jq '.custom | split (" ") | map(tonumber)')
                          | from json
              let screen_dimensions = (hyprctl monitors -j
                                       | jq -r 'map(select(.focused == true)) | .[] | {width: .width, height: .height}')
                                       | from json
              let window_dimensions = hyprctl activewindow -j
                                      | jq '.size | { width: .[0], height: .[1] }'
                                      | from json

              let gap_top = $gaps.0
              let gap_right = $gaps.1
              let gap_bottom = $gaps.2
              let gap_left = $gaps.3
              let screen_height = $screen_dimensions.height
              let screen_width = $screen_dimensions.width
              let window_height = $window_dimensions.height
              let window_width = $window_dimensions.width

              let window_left = $gap_left + $border_size
              let window_top = $gap_top + $border_size + $waybar_height + $border_size + $gap_top
              let window_right = $screen_width - $window_width - $gap_right - $border_size
              let window_bottom = $screen_height - $window_height - $gap_bottom - $border_size

              {
                window_left: $window_left,
                window_right: $window_right,
                window_bottom: $window_bottom,
                window_top: $window_top
              }
            }

            export def reset [] {
              hyprctl dispatch moveactive exact 0 0
            }

            export def topLeft [] {
              windowInfo
              | hyprctl dispatch moveactive exact $in.window_left $in.window_top
            }

            export def topRight [] {
              windowInfo
              | hyprctl dispatch moveactive exact $in.window_right $in.window_top
            }

            export def bottomRight [] {
              windowInfo
              | hyprctl dispatch moveactive exact $in.window_right $in.window_bottom
            }

            export def bottomLeft [] {
              windowInfo
              | hyprctl dispatch moveactive exact $in.window_left $in.window_bottom
            }
          '';
    in
    # sh
    ''
      nu -c "use ${nuScript} *; $1"
    '';
}
