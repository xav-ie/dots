{
  writeNuApplication,
  notify,
}:
writeNuApplication {
  name = "focus-or-open-application";
  runtimeInputs = [
    notify
    # yabai
  ];
  text = # nu
    ''
      def main [appName: string] {
        try {
          ^open (mdfind kMDItemContentTypeTree=com.apple.application-bundle
                | grep $'/($appName).app$')
          # TODO: add add window switching support (i.e. more than
          # one window open of app should switch windows on
          # re-invoke)
          # Also, make sure PiP windows never get focused on
          # let appId = (yabai -m query --windows
          #             | from json
          #             | where app == $"($appName)"
          #             | first
          #             | get id)
          # yabai -m window --focus $appId
        } catch {
          notify $"Could not focus or open '($appName)'"
        }
      }
    '';
}
