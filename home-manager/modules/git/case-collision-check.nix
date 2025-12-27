# Git config case sensitivity rules:
#   1. "Section names are case-insensitive"
#   2. "Subsection names are case sensitive"
#   3. "The variable names are case-insensitive"
#
# Reference: git-config(1) "CONFIGURATION FILE" section
# https://git.kernel.org/pub/scm/git/git.git/tree/Documentation/config.adoc
#
# Examples (git config syntax):
#   [core] vs [Core]                         -> SAME section
#   core.autocrlf vs core.autoCRLF           -> SAME variable
#   [branch "Main"] vs [branch "main"]       -> DIFFERENT subsections
#
# In Nix attrset representation:
#
#   { core = { ... }; }                      -> section (case-insensitive)
#   { Core = { ... }; }                      -> CONFLICT - same section
#
#   { core.autocrlf = "..."; }               -> variable (case-insensitive)
#   { core.autoCRLF = "..."; }               -> CONFLICT - same variable
#
#   { branch.Main = { ... }; }               -> subsection (case-sensitive)
#   { branch.main = { ... }; }               -> OK - different subsections
#
# We detect subsections by checking if the value is an attrset.
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.git;

  # Find keys that differ only in case AND have different values.
  # Returns list of detailed conflict descriptions.
  findConflicts =
    attrs:
    let
      keys = lib.attrNames attrs;
      grouped = builtins.groupBy lib.strings.toLower keys;
      # Only groups with multiple keys (case collisions)
      collisions = lib.filterAttrs (_: v: lib.length v > 1) grouped;
      # Filter to only those where values actually differ
      conflicting = lib.filterAttrs (
        _lower: keyList:
        let
          values = map (k: attrs.${k}) keyList;
          firstValue = lib.head values;
        in
        !lib.all (v: v == firstValue) values
      ) collisions;
      # Format each conflict with keys and values
      formatConflict =
        _lower: keyList:
        let
          keyValues = map (k: "${k} = ${lib.generators.toPretty { } attrs.${k}}") keyList;
        in
        lib.concatStringsSep "\n" keyValues;
    in
    lib.mapAttrsToList formatConflict conflicting;

  # Group sections by lowercase name to find collisions
  sectionKeys = lib.attrNames cfg.settings;
  sectionsByLower = builtins.groupBy lib.strings.toLower sectionKeys;

  # For each group of case-colliding sections, merge their contents and check
  # for variable conflicts across all of them
  checkSectionGroup =
    _lowerSection: sectionNames:
    let
      # Collect all variables from all case-variants of this section
      # Tag each with its original section name and variable name for error messages
      collectTaggedVars =
        sectionName:
        let
          sectionAttrs = cfg.settings.${sectionName};
          isSubsection = _name: val: lib.isAttrs val;
          variables = lib.filterAttrs (n: v: !isSubsection n v) sectionAttrs;
        in
        lib.mapAttrsToList (varName: val: {
          inherit val varName;
          path = "${sectionName}.${varName}";
        }) variables;

      # Merge all tagged variables from all section variants
      allTaggedVars = lib.concatLists (map collectTaggedVars sectionNames);

      # Group by lowercase variable name (not full path!)
      # This catches merge.f vs MERGE.f as the same variable
      varsByLower = builtins.groupBy (tv: lib.strings.toLower tv.varName) allTaggedVars;

      # Find groups where values differ
      findVarConflicts = lib.filterAttrs (
        _lower: tvList:
        let
          values = map (tv: tv.val) tvList;
          firstValue = lib.head values;
        in
        lib.length tvList > 1 && !lib.all (v: v == firstValue) values
      ) varsByLower;

      formatVarConflict =
        _lower: tvList:
        lib.concatMapStringsSep "\n" (tv: "${tv.path} = ${lib.generators.toPretty { } tv.val}") tvList;

      varConflicts = lib.mapAttrsToList formatVarConflict findVarConflicts;

      # Also check subsections within each section
      # Subsection NAMES are case-sensitive, so we check each section independently
      checkSubsections =
        sectionName:
        let
          sectionAttrs = cfg.settings.${sectionName};
          isSubsection = _name: val: lib.isAttrs val;
          subsections = lib.filterAttrs isSubsection sectionAttrs;
          addSubsectionPrefix =
            subName: c:
            lib.concatMapStringsSep "\n" (line: "${sectionName}.${subName}.${line}") (lib.splitString "\n" c);
        in
        lib.concatLists (
          lib.mapAttrsToList (
            subName: subAttrs: map (addSubsectionPrefix subName) (findConflicts subAttrs)
          ) subsections
        );

      subsectionConflicts = lib.concatLists (map checkSubsections sectionNames);
    in
    varConflicts ++ subsectionConflicts;

  # Check variables within each section (handles single sections)
  # For colliding sections, checkSectionGroup handles cross-section conflicts
  withinSectionConflicts = lib.concatLists (lib.mapAttrsToList checkSectionGroup sectionsByLower);

  # Section name conflicts (just list the names for awareness)
  sectionConflicts =
    let
      collisions = lib.filterAttrs (_: v: lib.length v > 1) sectionsByLower;
    in
    lib.mapAttrsToList (_: keyList: lib.concatStringsSep ", " keyList) collisions;

  allConflicts = sectionConflicts ++ withinSectionConflicts;

  # Format section conflicts (just list the conflicting names)
  formatSectionConflicts =
    if sectionConflicts == [ ] then
      ""
    else
      ''
        Section conflicts:
        ${lib.concatMapStringsSep "\n" (s: "  ${s}") sectionConflicts}
      '';

  # Format variable conflicts (show full paths with values)
  formatVariableConflicts =
    if withinSectionConflicts == [ ] then
      ""
    else
      ''
        Variable conflicts:
        ${lib.concatMapStringsSep "\n" (
          c: lib.concatMapStringsSep "\n" (line: "  ${line}") (lib.splitString "\n" c)
        ) withinSectionConflicts}
      '';

  formattedConflicts = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") [
      formatSectionConflicts
      formatVariableConflicts
    ]
  );
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = allConflicts == [ ];
        message = ''
          programs.git.settings contains keys that differ only in case but have different
          values.
          Git config section and variable names are case-insensitive, so only one value
          will be used and others silently discarded.

          ${formattedConflicts}
          Consider matching the casing. This will cause a Nix module conflict, which you
          may then resolve (e.g. via lib.mkForce).

          Example - before:
            merge.conflictstyle = "zdiff3";  # your config
            merge.conflictStyle = "diff3";   # from another module

          Example - after:
            merge.conflictStyle = lib.mkForce "zdiff3";  # match casing, set priority
        '';
      }
    ];
  };
}
