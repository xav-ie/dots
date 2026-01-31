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
      lib.replaceStrings [ "~${primaryUser}" ] [ "/Users/${primaryUser}" ] domain + ".plist"
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
      lib.strings.floatToString v
    else if lib.isString v then
      v
    else
      null;

  # Convert Nix value to PlistBuddy Print output format (for complex types)
  toPlistBuddyOutput =
    indent: v:
    let
      spaces = lib.concatStrings (lib.genList (_: "    ") indent);
      nextIndent = indent + 1;
    in
    if lib.isBool v then
      if v then "true" else "false"
    else if lib.isInt v then
      toString v
    else if lib.isFloat v then
      lib.strings.floatToString v
    else if lib.isString v then
      v
    else if lib.isList v then
      "Array {\n${
        lib.concatStringsSep "\n" (map (elem: "${spaces}    ${toPlistBuddyOutput nextIndent elem}") v)
      }\n${spaces}}"
    else if lib.isAttrs v then
      "Dict {\n${
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: val: "${spaces}    ${k} = ${toPlistBuddyOutput nextIndent val}") v
        )
      }\n${spaces}}"
    else
      toString v;

  # Hash PlistBuddy output for complex types
  hashPlistBuddyValue = value: builtins.hashString "sha256" (toPlistBuddyOutput 0 value + "\n");

  # Generate check command - use raw for simple types, PlistBuddy for complex
  # Runs in background, writes to $mismatch_file on mismatch
  mkKeyCheckCmd =
    plistPath: key: value:
    if isSimple value then
      let
        expected = toRawValue value;
      in
      "(actual=$(plutil -extract ${lib.escapeShellArg key} raw -o - ${lib.escapeShellArg plistPath} 2>/dev/null); [[ \"$actual\" != ${lib.escapeShellArg expected} ]] && echo 1 > \"$mismatch_file\") &"
    else
      let
        expectedHash = hashPlistBuddyValue value;
      in
      "(actual=$(/usr/libexec/PlistBuddy -c \"Print :${key}\" ${lib.escapeShellArg plistPath} 2>/dev/null | shasum -a 256 | cut -d' ' -f1); [[ \"$actual\" != \"${expectedHash}\" ]] && echo 1 > \"$mismatch_file\") &";

  # Collect all check commands as a list
  mkDomainCheckCmds =
    domain: attrs:
    let
      plistPath = domainToPath domain;
      filteredAttrs = lib.filterAttrs (_n: v: v != null) attrs;
    in
    lib.mapAttrsToList (mkKeyCheckCmd plistPath) filteredAttrs;

  # Filter out deprecated/aliased options
  dockFiltered = builtins.removeAttrs cfg.dock [ "expose-group-by-app" ];

  # All check commands as newline-separated string
  allCheckCmds = lib.concatStringsSep "\n" (
    lib.flatten [
      (mkDomainCheckCmds "com.apple.dock" dockFiltered)
      (mkDomainCheckCmds "com.apple.finder" cfg.finder)
      (mkDomainCheckCmds "-g" cfg.NSGlobalDomain)
      (mkDomainCheckCmds "com.apple.screencapture" cfg.screencapture)
      (mkDomainCheckCmds "com.apple.AppleMultitouchTrackpad" cfg.trackpad)
      (mkDomainCheckCmds "com.apple.driver.AppleBluetoothMultitouch.trackpad" cfg.trackpad)
      (lib.flatten (lib.mapAttrsToList mkDomainCheckCmds cfg.CustomUserPreferences))
    ]
  );
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
      (lib.mkAfter ''
        }
        # Check if defaults match expected state (pure bash parallel)
        echo "checking defaults..." >&2
        mismatch_file=$(mktemp)
        echo 0 > "$mismatch_file"
        ${allCheckCmds}
        wait
        if [[ "$(cat "$mismatch_file")" == "0" ]]; then
          echo "user defaults unchanged, skipping..." >&2
        else
          _nix_darwin_user_defaults
        fi
        rm -f "$mismatch_file"
      '')
    ];
  };
}
