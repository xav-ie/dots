{
  writeNuApplication,
  notify,
  yabai,
}:
writeNuApplication {
  name = "focus-or-open-application";
  runtimeInputs = [
    notify
    yabai
  ];
  text = # nu
    ''
      def main [appName: string] {
        try {
          let appId = (yabai -m query --windows
                      | from json
                      | where app   == $"($appName)" and
                              title != "Picture-in-Picture"
                      | last
                      | get id)
          yabai -m window --focus $appId
        } catch {
          try {
            ^open (mdfind kMDItemContentTypeTree=com.apple.application-bundle
                  | grep $'/($appName).app$')
          } catch {
            notify $"Could not focus or open '($appName)'"
          }
        }
      }
    '';
}
