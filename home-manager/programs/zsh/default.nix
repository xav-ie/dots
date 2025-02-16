{
  lib,
  pkgs,
  ...
}:
let
  tmux-tab-name-update = lib.getExe pkgs.pkgs-mine.is-sshed;
in
{
  config = {
    programs.zsh =
      let
        # TODO: move this and plugin config into a separate file
        fzfTabInitExtra = # sh
          ''
            # disable sort when completing `git checkout`
            zstyle ':completion:*:git-checkout:*' sort false
            # set descriptions format to enable group support
            # NOTE: don't use escape sequences here, fzf-tab will ignore them
            zstyle ':completion:*:descriptions' format '[%d]'
            # set list-colors to enable filename colorizing
            # zstyle ':completion:*' list-colors ''${("s.:.") LS_COLORS}
            # force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
            zstyle ':completion:*' menu no
            # preview directory's content with eza when completing cd
            zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
            # switch group using `<` and `>`
            zstyle ':fzf-tab:*' switch-group '<' '>'
          '';
      in
      {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        shellAliases = {
          # this is for commands that do not properly adjust their output to given width
          c4 = "COLUMNS=$COLUMNS-4";
          gake = "git pull && make";
          gp = "gh pr view";
          gpw = "gh pr view -w";
          info = "env info --vi-keys";
          l = "ls -lah";
          # I could not get man to respect pager width
          man = "c4 env man";
          # nvim = "~/Projects/xnixvim/result/bin/nvim";
          tm = "tmux attach || tmux";
          w = "watson";
          zj = "zellij attach || zellij";
        };
        initExtra = # sh
          ''
            ${fzfTabInitExtra}
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
              ${tmux-tab-name-update}
            }

            download_nixpkgs_cache_index () {
              filename="index-$(uname -m | sed 's/^arm64$/aarch64/')-$(uname | tr A-Z a-z)"
              mkdir -p ~/.cache/nix-index && cd ~/.cache/nix-index
              # -N will only download a new version if there is an update.
              wget -q -N https://github.com/Mic92/nix-index-database/releases/latest/download/$filename
              ln -f $filename files
            }
          '';
        plugins = [
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
        ];
      };
  };
}
