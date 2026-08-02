{
  flake.modules.homeManager.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      live = "${config.home.homeDirectory}/Library/Application Support/Claude/claude_desktop_config.json";
      repo = "${config.dotFilesDir}/modules/home-darwin/claude-desktop/claude_desktop_config.json";
    in
    {
      # Claude Desktop saves prefs by writing a temp file and rename()ing it over
      # the target, which replaces a symlink instead of following it — so
      # home.file/mkOutOfStoreSymlink silently stops tracking after the first save.
      # Instead: sync live -> repo on activation, so app changes land as a git diff
      # for review. Push the other way with `claude-config-push`.
      home.activation.claudeDesktopConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [ -e "${live}" ]; then
          if ! cmp -s "${live}" "${repo}"; then
            run cp -f "${live}" "${repo}"
            echo "claude-desktop: pulled live config into the repo — review with 'git diff'"
          fi
        else
          run install -m600 -D "${repo}" "${live}"
        fi
      '';

      home.packages = [
        # Force the repo's config back out to the live file, for when you've
        # hand-edited the repo copy and want the app to pick it up. The reverse
        # direction is automatic on every activation.
        (pkgs.writeShellApplication {
          name = "claude-config-push";
          runtimeInputs = [ pkgs.procps ];
          text = ''
            if pgrep -x Claude >/dev/null; then
              echo "Claude Desktop is running — quit it first, or it'll overwrite this on its next prefs save." >&2
              exit 1
            fi
            install -m600 -D "${repo}" "${live}"
            echo "pushed ${repo} -> ${live}"
          '';
        })
      ];
    };
}
