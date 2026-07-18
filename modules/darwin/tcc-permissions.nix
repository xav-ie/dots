{
  flake.modules.darwin.macos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.security.tcc;

      tccGrant = pkgs.pkgs-mine.tcc-grant;

      # These services live in the SYSTEM TCC.db (/Library/...); everything else
      # (Camera, Microphone, AppleEvents, …) lives in the per-user db. A grant to
      # the wrong db is silently inert — the long-standing bug this fixes.
      systemServices = [
        "Accessibility"
        "FullDiskAccess"
        "ScreenCapture"
        "DeveloperTool"
        "InputMonitoring"
        "PostEvent"
      ];
      dbFor = service: if builtins.elem service systemServices then "$SYS_TCC_DB" else "$USER_TCC_DB";

      # Generate grant commands for all apps and services
      grantCommands =
        cfg.apps
        |> lib.concatMapStringsSep "\n" (
          app:
          let
            # Apps whose bundle we mutate in place (e.g. Firefox autoconfig
            # injection) lose their Apple seal; under amfi_get_out_of_my_way=1 tccd
            # then treats them as unsigned platform binaries and denies everything.
            # The fix is to re-sign them with an Apple-anchored cert — that re-sign
            # happens in the owning module's *user-level* activation (it needs
            # keychain access) and runs before this one. Here we only pin the csreq.
            #
            # pin = "designated" (default): read the bundle's *current* designated
            # requirement (--designated-from). Cert-anchored, so it auto-tracks
            # whatever cert the re-sign used and survives rotation with no config
            # change. Correct for cert-signed apps (Firefox).
            #
            # pin = "cdhash": pin the raw cdhash (--app-path). For ad-hoc/self-signed
            # store bundles (e.g. focusd) that have no cert anchor for a DR; the
            # legacy-SHA-1 cdhash matches because the bundle is itself ad-hoc signed.
            pinArg =
              if app.appPath == "" then
                ""
              else if app.pin == "cdhash" then
                " --app-path \"${app.appPath}\""
              else
                " --designated-from \"${app.appPath}\"";

            services =
              app.services
              |> lib.concatMapStringsSep "\n" (
                service:
                "${tccGrant}/bin/tcc-grant --service ${service} --bundle-id ${app.bundleId} --db \"${dbFor service}\"${pinArg}"
              );
          in
          ''
            # ${app.bundleId}
            ${services}
          ''
        );

      # Resolve each app's reloadAgent (a launchd ATTR NAME) to a concrete
      # `launchctl kickstart` command, reading the real label + domain from the
      # launchd config already in scope (TCC only writes activation scripts and
      # launchd never reads security.tcc, so there's no eval cycle). A name that
      # matches no agent throws here — a build error, not a silent permission
      # starve. GUI apps (reloadAgent = null) contribute nothing.
      reloadCmds = lib.concatMap (
        app:
        lib.optional (app.reloadAgent != null) (
          let
            name = app.reloadAgent;
            inUser = config.launchd.user.agents ? ${name};
            inSys = config.launchd.daemons ? ${name};
            agent =
              if inUser then
                config.launchd.user.agents.${name}
              else if inSys then
                config.launchd.daemons.${name}
              else
                throw "security.tcc: reloadAgent \"${name}\" names no launchd.user.agents.<name> or launchd.daemons.<name>";
            label = agent.serviceConfig.Label or "org.nixos.${name}";
          in
          if inUser then
            ''sudo -u ${config.defaultUser} launchctl kickstart -k "gui/$(id -u ${config.defaultUser})/${label}"''
          else
            ''launchctl kickstart -k "system/${label}"''
        )
      ) cfg.apps;
    in
    {
      options.security.tcc = {
        enable = lib.mkEnableOption "declarative TCC permission management";

        apps = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                bundleId = lib.mkOption {
                  type = lib.types.str;
                  description = "Application bundle identifier (e.g., org.whispersystems.signal-desktop)";
                  example = "org.whispersystems.signal-desktop";
                };

                appPath = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = ''
                    Absolute path to the .app bundle. When set, the grant is pinned to
                    the bundle's current designated requirement (read at activation)
                    instead of a bare bundle-id match — required for re-signed apps,
                    whose ad-hoc/cert seal has no anchor a bundle-id grant can trust.
                  '';
                  example = "/Applications/Firefox.app";
                };

                pin = lib.mkOption {
                  type = lib.types.enum [
                    "designated"
                    "cdhash"
                  ];
                  default = "designated";
                  description = ''
                    How to pin the csreq when appPath is set. "designated" reads the
                    bundle's current designated requirement (cert-anchored, survives
                    cert rotation) — use for re-signed apps like Firefox. "cdhash"
                    pins the raw cdhash — use for ad-hoc/self-signed store bundles
                    (e.g. focusd) that have no cert anchor for a designated
                    requirement. Only meaningful together with appPath.
                  '';
                };

                resignIdentity = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = ''
                    Coarse codesign-identity matcher (a substring of the cert name, e.g.
                    "Apple Development") that the app's bundle is re-signed with. This
                    module does NOT use it directly — the owning module reads it (via
                    osConfig) and resolves the exact identity from the login keychain at
                    activation, so cert rotation needs no config change. Declared here so
                    intent lives next to the grant; pair with appPath.

                    Needed for bundles mutated in place — e.g. Firefox, whose autoconfig
                    injection breaks the Apple seal; under amfi_get_out_of_my_way=1 a
                    broken/ad-hoc seal makes tccd treat the app as an unsigned platform
                    binary and deny camera/mic/screen-capture. Must resolve to an
                    Apple-anchored cert (ad-hoc does not work).
                  '';
                  example = "Apple Development";
                };

                services = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.enum [
                      # Media
                      "Camera"
                      "Microphone"
                      "ScreenCapture"
                      # Automation
                      "Accessibility"
                      "AppleEvents"
                      "InputMonitoring"
                      # Data
                      "AddressBook"
                      "Calendar"
                      "Reminders"
                      "Photos"
                      # System
                      "SpeechRecognition"
                      "FullDiskAccess"
                      "DownloadsFolder"
                      "DesktopFolder"
                      "DocumentsFolder"
                      "Location"
                      "FocusStatus"
                    ]
                  );
                  default = [
                    "Camera"
                    "Microphone"
                  ];
                  description = "TCC services to grant access to";
                };

                reloadAgent = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "focusd";
                  description = ''
                    The launchd ATTRIBUTE NAME (e.g. "focusd" for
                    launchd.user.agents.focusd or launchd.daemons.focusd — NOT the
                    full "org.nixos.focusd" label) of a background daemon THIS config
                    manages that must be relaunched after this app's grant is
                    (re)written. TCC latches an app's authorization per process
                    launch, and nix-darwin loads agents BEFORE this activation writes
                    the grant, so a daemon that checks its own auth at launch
                    (AXIsProcessTrusted(), creating a CGEventTap, …) caches a
                    pre-grant "denied" and stays starved until relaunched.

                    The module resolves the real launchd label + kickstart domain
                    from config, and THROWS at eval if the name matches no agent —
                    so a typo becomes a build error, never a silently un-granted
                    daemon. Leave null for GUI apps (Firefox, Signal, …); you never
                    want to force-restart those, and the user relaunches them anyway.
                  '';
                };
              };
            }
          );
          default = [ ];
          description = "Applications to grant TCC permissions to";
          example = lib.literalExpression ''
            [
              { bundleId = "org.whispersystems.signal-desktop"; services = [ "Camera" "Microphone" "ScreenCapture" ]; }
              { bundleId = "com.mitchellh.ghostty"; services = [ "Accessibility" "FullDiskAccess" ]; }
            ]
          '';
        };
      };

      config = lib.mkIf (cfg.enable && cfg.apps != [ ]) {
        # Grant at activation (runs as root). System-db writes work because SIP is
        # off; reload tccd so it picks them up without a logout. tcc-grant skips
        # already-allowed entries, so existing System-Settings grants are safe.
        system.activationScripts.postActivation.text = lib.mkAfter ''
          echo "Ensuring TCC permissions for ${config.defaultUser}..."
          USER_TCC_DB="/Users/${config.defaultUser}/Library/Application Support/com.apple.TCC/TCC.db"
          SYS_TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
          ${grantCommands}
          sudo -u ${config.defaultUser} launchctl kickstart -k \
            "gui/$(id -u ${config.defaultUser})/com.apple.tccd" 2>/dev/null || true
          ${lib.optionalString (reloadCmds != [ ]) ''
            # Relaunch the managed daemons whose grant we just (re)wrote, so they
            # re-evaluate their launch-cached authorization against the live grant
            # (see the reloadAgent option). Guarded by a hash of the grant config
            # (which includes each app's store path, so it changes when a granted
            # binary is rebuilt) so a no-op `just system` doesn't SIGKILL-restart
            # them every time.
            reload_hash="${builtins.hashString "sha256" (builtins.toJSON cfg.apps)}"
            reload_marker="/var/lib/nix-darwin/tcc-reload.hash"
            if [ "$(cat "$reload_marker" 2>/dev/null)" != "$reload_hash" ]; then
              # tccd kickstart above is async and exposes no readiness signal; give
              # it a moment to reload the freshly-written db before agents re-check.
              sleep 1
              ${lib.concatMapStringsSep "\n" (cmd: "${cmd} 2>/dev/null || true") reloadCmds}
              mkdir -p "$(dirname "$reload_marker")"
              echo "$reload_hash" > "$reload_marker"
            fi
          ''}
        '';
      };
    };
}
