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

      # Only the keys set on purpose. The app owns everything else in the file
      # (pane layout, pins, per-account flags) and rewrites it constantly.
      managed = pkgs.writeText "claude-desktop-managed.json" (
        builtins.toJSON {
          coworkUserFilesPath = "${config.home.homeDirectory}/Claude";
          mcpServers.executor = {
            command = "/etc/profiles/per-user/${config.home.username}/bin/executor-mcp-remote";
            args = [ ];
          };
          preferences = {
            ccRemoteControlDefaultEnabled = true;
            ccdScheduledTasksEnabled = true;
            chicagoEnabled = true;
            coworkScheduledTasksEnabled = true;
            coworkWebSearchEnabled = true;
            keepAwakeEnabled = true;
            menuBarEnabled = false;
            remoteToolsDeviceName = "nox";
            sidebarMode = "chat";
          };
        }
      );
    in
    {
      # Deep-merge the managed keys into the live file, leaving the app's own
      # state alone. Claude Desktop holds prefs in memory and saves them whole,
      # so quit it before switching for a change here to stick.
      home.activation.claudeDesktopConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        live="${live}"
        if [ -s "$live" ]; then
          if ! ${pkgs.jq}/bin/jq -e --slurpfile m ${managed} '. == (. * $m[0])' "$live" >/dev/null; then
            tmp=$(mktemp)
            ${pkgs.jq}/bin/jq --slurpfile m ${managed} '. * $m[0]' "$live" > "$tmp"
            run install -m600 "$tmp" "$live"
            rm -f "$tmp"
          fi
        else
          run install -m600 -D ${managed} "$live"
        fi
      '';

      home.packages = [
        # Executor gates /mcp on a bearer token. The managed config lands in the
        # world-readable store, so the token can't live in it — read it out of the
        # sops shell-env blob at launch instead. A GUI app also carries none of
        # the shell env, so ${EXECUTOR_AUTH_TOKEN} wouldn't expand there anyway.
        (pkgs.writeShellApplication {
          name = "executor-mcp-remote";
          runtimeInputs = [ pkgs.nodejs ];
          text = # sh
            ''
              for var in EXECUTOR_AUTH_TOKEN CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
                val=$(sed -n "s/^$var=//p" /run/secrets/shell-env)
                if [ -z "$val" ]; then
                  echo "executor-mcp-remote: $var missing from /run/secrets/shell-env" >&2
                  exit 1
                fi
                export "$var=$val"
              done

              # Secrets go through the environment, never argv: /proc/PID/cmdline
              # is world-readable (mode 444) while environ is 400. mcp-remote expands
              # ''${VAR} in header values from its own process env. The CF-Access-*
              # pair is a Cloudflare Access service token (Service Auth policy on /mcp).
              exec npx -y mcp-remote https://executor.lalala.casa/mcp \
                --header "Authorization:Bearer \''${EXECUTOR_AUTH_TOKEN}" \
                --header "CF-Access-Client-Id:\''${CF_ACCESS_CLIENT_ID}" \
                --header "CF-Access-Client-Secret:\''${CF_ACCESS_CLIENT_SECRET}"
            '';
        })
      ];
    };
}
