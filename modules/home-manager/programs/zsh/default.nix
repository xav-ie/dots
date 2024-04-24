{ pkgs, ... }:
{
  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        # this is for commands that do not properly adjust their output to given width
        c4 = "COLUMNS=$COLUMNS-4";
        info = "env info --vi-keys";
        # I could not get man to respect pager width
        man = "c4 env man";
        # nvim = "~/Projects/xnixvim/result/bin/nvim";
        w = "watson";
        zj = "zellij attach || zellij";
      };
      initExtra = # sh
        ''
          # comment this if you face weird direnv issues
          export DIRENV_LOG_FORMAT=""

          function git_diff_exclude_file() {
            if [ $# -lt 3 ]; then
              echo "Usage: git_diff_exclude_file <start_commit> <end_commit> <exclude_file> [output_file]"
              return 1
            fi

            local start_commit=$1
            local end_commit=$2
            local exclude_file=$3
            local output_file=$\{4:-combined_diff.txt}

            git diff --name-only "$start_commit" "$end_commit" | grep -v "$exclude_file" | xargs -I {} git diff "$start_commit" "$end_commit" -- {} > "$output_file"
          }

          source $HOME/.env

          precmd() {
            ${pkgs.zellij-tab-name-update}/bin/zellij-tab-name-update
          }

          download_nixpkgs_cache_index () {
            filename="index-$(uname -m | sed 's/^arm64$/aarch64/')-$(uname | tr A-Z a-z)"
            mkdir -p ~/.cache/nix-index && cd ~/.cache/nix-index
            # -N will only download a new version if there is an update.
            wget -q -N https://github.com/Mic92/nix-index-database/releases/latest/download/$filename
            ln -f $filename files
          }
        '';
    };
  };
}
