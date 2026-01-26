{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.programs.ralph;

  # Build ralph with the patch applied
  ralph = pkgs.stdenv.mkDerivation {
    pname = "ralph";
    version = "unstable";

    src = inputs.ralph-src;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/share/ralph/skills

      # Install prompt files
      cp prompt.md $out/share/ralph/
      cp CLAUDE.md $out/share/ralph/

      # Install skills
      cp -r skills/* $out/share/ralph/skills/

      # Patch ralph.sh to:
      # 1. Use PWD for project files (prd.json, progress.txt)
      # 2. Use nix store for prompt templates
      substituteInPlace ralph.sh \
        --replace-fail '#!/bin/bash' '#!/usr/bin/env bash' \
        --replace-fail 'TOOL="amp"' 'TOOL="claude"' \
        --replace-fail 'SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"' 'SCRIPT_DIR="$(pwd)"' \
        --replace-fail '$SCRIPT_DIR/prompt.md' "$out/share/ralph/prompt.md" \
        --replace-fail '$SCRIPT_DIR/CLAUDE.md' "$out/share/ralph/CLAUDE.md"
      cp ralph.sh $out/bin/ralph
      chmod +x $out/bin/ralph

      # Wrap to add dependencies to PATH
      wrapProgram $out/bin/ralph \
        --prefix PATH : "${
          lib.makeBinPath [
            pkgs.jq
            pkgs.git
          ]
        }"

      runHook postInstall
    '';

    meta = {
      description = "Autonomous AI agent loop for completing PRDs";
      homepage = "https://github.com/snarktank/ralph";
      mainProgram = "ralph";
    };
  };
in
{
  options.programs.ralph = {
    enable = lib.mkEnableOption "Ralph autonomous AI agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = ralph;
      description = "The ralph package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Symlink skills to Claude's skills directory
    home.file.".claude/skills/prd".source =
      config.lib.file.mkOutOfStoreSymlink "${cfg.package}/share/ralph/skills/prd";
    home.file.".claude/skills/ralph".source =
      config.lib.file.mkOutOfStoreSymlink "${cfg.package}/share/ralph/skills/ralph";
  };
}
