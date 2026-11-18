# Notifier.app as a resident agent: it handles notification clicks, removes
# expired notifications, and greets the work morning on login, wake and
# unlock. See packages/notifier and packages/notify.
{
  flake.modules.homeManager.darwin =
    { pkgs, lib, ... }:
    let
      # praesidium's start-work holds the once-a-day claim for both machines;
      # exit 0 means this wake is the first of the work morning.
      good-morning = pkgs.writeNuApplication {
        name = "good-morning";
        runtimeInputs = [
          pkgs.openssh
          pkgs.pkgs-mine.notify
        ];
        text = # nu
          ''
            let claim = ^ssh -o BatchMode=yes -o ConnectTimeout=5 praesidium start-work | complete
            if $claim.exit_code == 0 {
              notify "Good morning" "Time to start work!" --icon morning --expire 12hr
            }
          '';
      };
    in
    {
      launchd.agents.notifier = {
        enable = true;
        config = {
          ProgramArguments = [
            "${pkgs.pkgs-mine.notifier}/Applications/Notifier.app/Contents/MacOS/notifier"
            "--on-wake"
            (lib.getExe good-morning)
          ];
          KeepAlive = true;
          RunAtLoad = true;
          ProcessType = "Interactive";
          StandardErrorPath = "/tmp/notifier.err";
        };
      };
    };
}
