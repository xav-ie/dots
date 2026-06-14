{
  flake.modules.darwin.macos =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.system.defaults;
      inherit (config.system) primaryUser;
      prefsDir = "/Users/${primaryUser}/Library/Preferences";

      # Map domain names to plist file paths
      domainToPath =
        domain:
        if domain == "-g" || domain == "NSGlobalDomain" then
          "${prefsDir}/.GlobalPreferences.plist"
        else if lib.hasPrefix "~" domain then
          (domain |> lib.replaceStrings [ "~${primaryUser}" ] [ "/Users/${primaryUser}" ]) + ".plist"
        else if lib.hasPrefix "/" domain then
          domain + ".plist"
        else
          "${prefsDir}/${domain}.plist";

      # Check if value is a simple type (not list or attrset)
      isSimple = v: !(lib.isList v || lib.isAttrs v);

      # Convert simple Nix value to expected plutil raw output
      toRawValue =
        v:
        if lib.isBool v then
          if v then "true" else "false"
        else if lib.isInt v then
          toString v
        else if lib.isFloat v then
          v |> lib.strings.floatToString
        else if lib.isString v then
          v
        else
          null;

      # Convert Nix value to PlistBuddy Print output format (for complex types)
      toPlistBuddyOutput =
        indent: v:
        let
          spaces = lib.genList (_: "    ") indent |> lib.concatStrings;
          nextIndent = indent + 1;
        in
        if lib.isBool v then
          if v then "true" else "false"
        else if lib.isInt v then
          toString v
        else if lib.isFloat v then
          v |> lib.strings.floatToString
        else if lib.isString v then
          v
        else if lib.isList v then
          "Array {\n${
            v |> map (elem: "${spaces}    ${toPlistBuddyOutput nextIndent elem}") |> lib.concatStringsSep "\n"
          }\n${spaces}}"
        else if lib.isAttrs v then
          "Dict {\n${
            v
            |> lib.mapAttrsToList (k: val: "${spaces}    ${k} = ${toPlistBuddyOutput nextIndent val}")
            |> lib.concatStringsSep "\n"
          }\n${spaces}}"
        else
          toString v;

      # Hash PlistBuddy output for complex types
      hashPlistBuddyValue = value: (toPlistBuddyOutput 0 value + "\n") |> builtins.hashString "sha256";

      # Generate check command - use raw for simple types, PlistBuddy for complex
      # Runs in background, writes to $mismatch_file on mismatch and appends a
      # diagnostic line to $drift_log so the activation can name what drifted.
      mkKeyCheckCmd =
        plistPath: key: value:
        let
          where = "${plistPath} :: ${key}" |> lib.escapeShellArg;
        in
        if isSimple value then
          let
            expected = toRawValue value;
          in
          "(actual=$(plutil -extract ${key |> lib.escapeShellArg} raw -o - ${
            plistPath |> lib.escapeShellArg
          } 2>/dev/null); [[ \"$actual\" != ${expected |> lib.escapeShellArg} ]] && { echo 1 > \"$mismatch_file\"; printf '  drift: %s  expected=%s actual=%s\\n' ${where} ${expected |> lib.escapeShellArg} \"$actual\" >> \"$drift_log\"; }) &"
        else
          let
            expectedHash = hashPlistBuddyValue value;
          in
          "(actual=$(/usr/libexec/PlistBuddy -c \"Print :${key}\" ${
            plistPath |> lib.escapeShellArg
          } 2>/dev/null | shasum -a 256 | cut -d' ' -f1); [[ \"$actual\" != \"${expectedHash}\" ]] && { echo 1 > \"$mismatch_file\"; printf '  drift: %s  (complex value, expected hash=%s actual hash=%s)\\n' ${where} ${
            expectedHash |> lib.escapeShellArg
          } \"$actual\" >> \"$drift_log\"; }) &";

      # Collect all check commands as a list
      mkDomainCheckCmds =
        domain: attrs:
        let
          plistPath = domainToPath domain;
          filteredAttrs = lib.filterAttrs (_n: v: v != null) attrs;
        in
        filteredAttrs |> lib.mapAttrsToList (mkKeyCheckCmd plistPath);

      # Filter out deprecated/aliased options
      dockFiltered = removeAttrs cfg.dock [ "expose-group-by-app" ];

      # All check commands as newline-separated string. Every entry is a
      # domain → attrs mapping, so run mkDomainCheckCmds over each. Kept as
      # separate maps (not merged) because CustomUserPreferences may repeat a
      # fixed domain (e.g. trackpad) and both sets of checks must still run.
      allCheckCmds =
        [
          {
            "com.apple.dock" = dockFiltered;
            "com.apple.finder" = cfg.finder;
            "-g" = cfg.NSGlobalDomain;
            "com.apple.screencapture" = cfg.screencapture;
            "com.apple.AppleMultitouchTrackpad" = cfg.trackpad;
            "com.apple.driver.AppleBluetoothMultitouch.trackpad" = cfg.trackpad;
          }
          cfg.CustomUserPreferences
        ]
        |> lib.concatMap (lib.mapAttrsToList mkDomainCheckCmds)
        |> lib.flatten
        |> lib.concatStringsSep "\n";
    in
    {
      options.system.defaultsOptimization.enable =
        lib.mkEnableOption "verify defaults state before applying"
        // {
          default = true;
        };

      config = lib.mkIf config.system.defaultsOptimization.enable {
        system.activationScripts.userDefaults.text = lib.mkMerge [
          (lib.mkBefore ''
            _nix_darwin_user_defaults() {
          '')
          (lib.mkAfter # sh
            ''
              }
              # Check if defaults match expected state (pure bash parallel)
              echo "checking defaults..." >&2
              mismatch_file=$(mktemp)
              drift_log=$(mktemp)
              echo 0 > "$mismatch_file"
              ${allCheckCmds}
              wait
              if [[ "$(cat "$mismatch_file")" == "0" ]]; then
                echo "user defaults unchanged, skipping..." >&2
              else
                echo "user defaults drifted — re-applying. Drifted keys:" >&2
                cat "$drift_log" >&2
                _nix_darwin_user_defaults
              fi
              rm -f "$mismatch_file" "$drift_log"
            ''
          )
        ];
      };
    };
}
