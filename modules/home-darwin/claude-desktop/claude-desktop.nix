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
      # Claude Desktop saves prefs with a tmp+rename, which replaces a symlink
      # rather than following it, so mkOutOfStoreSymlink stops tracking after
      # the first save. Sync live -> repo on activation instead, so app changes
      # land as a git diff. Push the other way with `claude-config-push`.
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
        # Executor gates /mcp on a bearer token. The config JSON is committed and
        # synced both ways, so the token can't live in it — read it out of the
        # sops shell-env blob at launch instead. A GUI app also carries none of
        # the shell env, so ${EXECUTOR_AUTH_TOKEN} wouldn't expand there anyway.
        (pkgs.writeShellApplication {
          name = "executor-mcp-remote";
          runtimeInputs = [ pkgs.nodejs ];
          text = ''
            EXECUTOR_AUTH_TOKEN=$(sed -n 's/^EXECUTOR_AUTH_TOKEN=//p' /run/secrets/shell-env)
            if [ -z "$EXECUTOR_AUTH_TOKEN" ]; then
              echo "executor-mcp-remote: EXECUTOR_AUTH_TOKEN missing from /run/secrets/shell-env" >&2
              exit 1
            fi
            export EXECUTOR_AUTH_TOKEN

            # The token goes through the environment, never argv: /proc/PID/cmdline
            # is world-readable (mode 444) while environ is 400. mcp-remote expands
            # ''${VAR} in header values from its own process env.
            exec npx -y mcp-remote https://executor.lalala.casa/mcp \
              --header "Authorization:Bearer \''${EXECUTOR_AUTH_TOKEN}"
          '';
        })

        # Force the repo's config back out to the live file, after editing the
        # repo copy by hand.
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
