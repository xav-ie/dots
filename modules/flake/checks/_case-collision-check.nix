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
#
# This module exports check results for use by flake checks.
# Run `nix flake check` or `just check` to validate git config.
{ lib, gitSettings }:
let
  # Find keys that differ only in case AND have different values.
  # Returns list of detailed conflict descriptions.
  findConflicts =
    attrs:
    let
      keys = attrs |> lib.attrNames;
      grouped = keys |> builtins.groupBy lib.strings.toLower;
      # Only groups with multiple keys (case collisions)
      collisions = grouped |> lib.filterAttrs (_: v: (v |> lib.length) > 1);
      # Filter to only those where values actually differ
      conflicting =
        collisions
        |> lib.filterAttrs (
          _lower: keyList:
          let
            values = keyList |> map (k: attrs.${k});
            firstValue = values |> lib.head;
          in
          !(values |> lib.all (v: v == firstValue))
        );
      # Format each conflict with keys and values
      formatConflict =
        _lower: keyList:
        let
          keyValues = keyList |> map (k: "${k} = ${lib.generators.toPretty { } attrs.${k}}");
        in
        keyValues |> lib.concatStringsSep "\n";
    in
    conflicting |> lib.mapAttrsToList formatConflict;

  # Group sections by lowercase name to find collisions
  sectionKeys = gitSettings |> lib.attrNames;
  sectionsByLower = sectionKeys |> builtins.groupBy lib.strings.toLower;

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
          sectionAttrs = gitSettings.${sectionName};
          isSubsection = _name: val: builtins.isAttrs val;
          variables = sectionAttrs |> lib.filterAttrs (n: v: !isSubsection n v);
        in
        variables
        |> lib.mapAttrsToList (
          varName: val: {
            inherit val varName;
            path = "${sectionName}.${varName}";
          }
        );

      # Merge all tagged variables from all section variants
      allTaggedVars = sectionNames |> map collectTaggedVars |> lib.concatLists;

      # Group by lowercase variable name (not full path!)
      # This catches merge.f vs MERGE.f as the same variable
      varsByLower = allTaggedVars |> builtins.groupBy (tv: lib.strings.toLower tv.varName);

      # Find groups where values differ
      findVarConflicts =
        varsByLower
        |> lib.filterAttrs (
          _lower: tvList:
          let
            values = tvList |> map (tv: tv.val);
            firstValue = values |> lib.head;
          in
          (tvList |> lib.length) > 1 && !(values |> lib.all (v: v == firstValue))
        );

      formatVarConflict =
        _lower: tvList:
        tvList |> lib.concatMapStringsSep "\n" (tv: "${tv.path} = ${lib.generators.toPretty { } tv.val}");

      varConflicts = findVarConflicts |> lib.mapAttrsToList formatVarConflict;

      # Also check subsections within each section
      # Subsection NAMES are case-sensitive, so we check each section independently
      checkSubsections =
        sectionName:
        let
          sectionAttrs = gitSettings.${sectionName};
          isSubsection = _name: val: builtins.isAttrs val;
          subsections = sectionAttrs |> lib.filterAttrs isSubsection;
          addSubsectionPrefix =
            subName: c:
            lib.splitString "\n" c |> lib.concatMapStringsSep "\n" (line: "${sectionName}.${subName}.${line}");
        in
        subsections
        |> lib.mapAttrsToList (
          subName: subAttrs: findConflicts subAttrs |> map (addSubsectionPrefix subName)
        )
        |> lib.concatLists;

      subsectionConflicts = sectionNames |> map checkSubsections |> lib.concatLists;
    in
    varConflicts ++ subsectionConflicts;

  # Check variables within each section (handles single sections)
  # For colliding sections, checkSectionGroup handles cross-section conflicts
  withinSectionConflicts = sectionsByLower |> lib.mapAttrsToList checkSectionGroup |> lib.concatLists;

  # Section name conflicts (just list the names for awareness)
  sectionConflicts =
    let
      collisions = sectionsByLower |> lib.filterAttrs (_: v: (v |> lib.length) > 1);
    in
    collisions |> lib.mapAttrsToList (_: keyList: keyList |> lib.concatStringsSep ", ");

  allConflicts = sectionConflicts ++ withinSectionConflicts;

  # Format section conflicts (just list the conflicting names)
  formatSectionConflicts =
    if sectionConflicts == [ ] then
      ""
    else
      ''
        Section conflicts:
        ${sectionConflicts |> lib.concatMapStringsSep "\n" (s: "  ${s}")}
      '';

  # Format variable conflicts (show full paths with values)
  formatVariableConflicts =
    if withinSectionConflicts == [ ] then
      ""
    else
      # txt
      ''
        Variable conflicts:
        ${
          withinSectionConflicts
          |> lib.concatMapStringsSep "\n" (
            c: c |> lib.splitString "\n" |> lib.concatMapStringsSep "\n" (line: "  ${line}")
          )
        }
      '';

  formattedConflicts =
    [
      formatSectionConflicts
      formatVariableConflicts
    ]
    |> lib.filter (s: s != "")
    |> lib.concatStringsSep "\n";
in
{
  issues = allConflicts;

  hasErrors = allConflicts != [ ];

  errorMessage =
    if allConflicts == [ ] then
      ""
    else
      # txt
      ''
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
