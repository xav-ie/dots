{
  writeNuApplication,
  fzf,
  jq,
  yabai,
}:
writeNuApplication {
  name = "move-pip";
  runtimeInputs = [
    fzf
    jq
    yabai
  ];
  text = # nu
    ''
      def get-pip-info []: nothing -> record<w: float, h: float, x: float, y: float, id: int, display: int> {
        try {
          yabai -m query --windows
          | jq -r '[.[] | select(.title=="Picture-in-Picture")][0]'
          | from json
          | {
              w: $in.frame.w,
              h: $in.frame.h,
              x: $in.frame.x,
              y: $in.frame.y,
              id: $in.id,
              display: $in.display
            }
        } catch {
          error make --unspanned {
            msg: "Could not find any PiP windows."
          }
        }
      }

      def get-screen-id-dimensions [screenId: int]: nothing -> record<screenWidth: float, screenHeight: float> {
        yabai -m query --displays
        | jq --argjson id $"($screenId)" '.[] | select(.id==$id) | {screenWidth: .frame.w, screenHeight: .frame.h}'
        | from json
      }

      # returns both the pip and containing screen dimensions
      def get-pip-info-full []: nothing -> record<w: float, h: float, x: float, y: float, id: int, display: int, screenWidth: float, screenHeight: float> {
        let pipInfo = (get-pip-info)
        let screenDimensions = get-screen-id-dimensions ($pipInfo.display)
        {
          ...$pipInfo,
          ...$screenDimensions
        }
      }

      export def main [] {
        help main
      }

      # move window to top left
      export def "main top-left" []: nothing -> nothing {
        let pipInfo = (get-pip-info-full)
        yabai -m window $"($pipInfo.id)" --move abs:0:0
      }

      # move window to top right
      export def "main top-right" []: nothing -> nothing {
        let pipInfo = (get-pip-info-full)
        let moveX = $pipInfo.screenWidth - $pipInfo.w
        yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):0"
      }

      # move window to bottom right
      export def "main bottom-right" []: nothing -> nothing {
        let pipInfo = (get-pip-info-full)
        let moveX = $pipInfo.screenWidth - $pipInfo.w
        let moveY = $pipInfo.screenHeight - $pipInfo.h
        yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):($moveY)"
      }

      # move window to bottom left
      export def "main bottom-left" []: nothing -> nothing {
        let pipInfo = (get-pip-info-full)
        let moveY = $pipInfo.screenHeight - $pipInfo.h
        yabai -m window $"($pipInfo.id)" --move $"abs:0:($moveY)"
      }
    '';
}
