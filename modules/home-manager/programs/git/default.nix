{ }:
{
  programs = {
    git = {
      enable = true;
      userName = "xav-ie";
      # userEmail = "github@xav.ie";
      aliases = {
        bb = "!${./dotfiles/betterbranch.sh}";
        bblame = "blame -w -C -C -C";
        cam = "commit -am";
        c = "commit";
        dc = "diff --cached --ignore-all-space --ignore-space-at-eol --ignore-space-change --ignore-blank-lines -- . ':(exclude)*package-lock.json' -- . ':(exclude)*yarn.lock'";
        d = "diff --ignore-all-space --ignore-space-at-eol --ignore-space-change --ignore-blank-lines -- . ':(exclude)*package-lock.json' -- . ':(exclude)*yarn.lock'";
        graph = "log --graph --pretty=tformat:'%C(bold blue)%h%Creset %s %C(bold green)%d%Creset %C(blue)<%an>%Creset %C(dim cyan)%cr' --abbrev-commit --decorate";
        main = # sh
          "!(git fetch && git fetch --tags && git checkout -B main origin/main)";
        p = "push";
        pr = # sh
          ''
            !(GH_FORCE_TTY=100% gh pr list | fzf --ansi --preview 'GH_FORCE_TTY=100% gh pr view {1}' --preview-window up --header-lines 3 | awk '{print $1}' | xargs -r gh pr checkout)
          '';
        rmc = "rm --cached";
        s = "status";
        staash = "stash --all";
        # git log -L :functionName:/path/to/file
        # git blame -L :functionName:/path/to/file
        # git log -S your_regex -p 
        # git reflog <- idk what this does other than show history
        # "So You Think You Know Git - Part 2":
        # https://www.youtube.com/watch?v=Md44rcw13k4
        # Helpful hooks
        ## Commit Stuff
        # - pre-commit
        # - prepare-commit-msg
        # - commit-msg
        # - post-commit
        ## Rewriting stuff
        # - pre-rebase
        # - post-rewrite
        ## Merging Stuff
        # - post-merge
        # - pre-merge-commit
        ## Switching/Pushing Stuff
        # - post-checkout
        # - reference-transaction
        # - pre-push
        # He recommends `pre-commit` binary
      };
      # attributes = {
      # };
      # I am guessing this option sets up the options I set in extraConfig
      delta = {
        # I think it might not be worth it to turn this off and try and set up
        # yourself. There is a lot of set up this one flag does
        enable = true;
        options = {
          navigate = true;
          line-numbers = true;
          true-color = "always";
          dark = true;
        };
      };
      extraConfig = {
        core = {
          # configured by delta.enable=true
          # actually had to override that ^ 
          # in order to get better column width output
          # pager = "delta -n -w $(expr $COLUMNS - 4)";
          # pager = "delta";
        };
        branch.sort = "-committerdate";
        column.ui = "auto";
        # This is *very* helpful for stacked branches.
        # This is the situation.
        # You are on your third stacked PR.
        # You `git rebase -i main` to update your stacked PRs with main
        # Womp. PR 1 and PR 2 are *not* rebased when PR 3 is. Why is this the default? :shrug:
        # To lean more, go to: https://youtu.be/Md44rcw13k4?t=956
        # This article is also a great read on stacked PRs:
        # https://andrewlock.net/working-with-stacked-branches-in-git-is-easier-with-update-refs/
        # to temporarily turn off, --no-update-refs
        rebase.updateRefs = true;
        rerere.enabled = true;
        fetch.writeCommitGraph = true;
        remote.origin.fetch = "+refs/pull/*:refs/remotes/origin/pull/*";
        interactive = {
          # configured by delta.enable=true
          # this is used for diff patches
          # diffFilter = "delta";
        };
        # configured by delta.enable=true
        # delta = {
        #   navigate = true;
        #   line-numbers = true;
        #   true-color = "always";
        # };
        init = {
          defaultBranch = "main";
        };
        merge = {
          conflictstyle = "diff3";
        };
        diff = {
          colorMoved = "default";
        };
        "includeIf \"gitdir:~/\"" = {
          path = "~/.config/git/config.default";
        };
        "includeIf \"gitdir:~/Outsmartly/\"" = {
          path = "~/.config/git/config.work";
        };
      };
    };
  };
  home.file.".config/git/config.default".source = ./dotfiles/default.gitconfig;
  home.file.".config/git/config.work".source = ./dotfiles/outsmartly.gitconfig;
}
