{ lib, pkgs, ... }:
let
  gitIniFmt = pkgs.formats.gitIni { };
in
{
  config = {
    programs.git = {
      enable = true;
      userName = "xav-ie";
      # userEmail = "github@xav.ie";
      aliases =
        let
          diffTweaks = builtins.concatStringsSep " " [
            "--ignore-all-space"
            "--ignore-space-at-eol"
            "--ignore-space-change"
            "--ignore-blank-lines"
            "--patch-with-stat"
            "--"
            "."
            "':(exclude)*lock.json'"
            "--"
            "."
            "':(exclude)*.lock'"
          ];
        in
        {
          # aliases are case-insensitive
          B = "checkout -B";
          bb = "!${lib.getExe pkgs.pkgs-mine.better-branch}";
          blame-better = "blame -w -C -C -C";
          cam = "commit -am";
          c = "commit";
          chekcout = "checkout";
          cm = "commit -m";
          d = "diff ${diffTweaks}";
          dc = "diff --cached ${diffTweaks}";
          ds = "!git d && git s";
          graph =
            let
              columns = builtins.concatStringsSep " " [
                "%C(bold blue)%h%Creset"
                "%s"
                "%C(bold green)%d%Creset"
                "%C(blue)<%an>%Creset"
                "%C(dim cyan)%cr"
              ];
            in
            "log --graph --pretty=tformat:'${columns}' --abbrev-commit --decorate";
          main = # sh
            "!(git fetch && git fetch --tags && git checkout -B main origin/main)";
          patch = "show --patch";
          pull-force = "!git fetch && git reset --hard origin/$(git branch --show-current)";
          p = "push";
          pr = # sh
            ''
              !(GH_FORCE_TTY=100% gh pr list \
                | fzf --ansi --preview 'GH_FORCE_TTY=100% gh pr view {1}' \
                    --preview-window up --header-lines 3 \
                | awk '{print $1}' \
                | xargs -r gh pr checkout)
            '';
          rmc = "rm --cached";
          s = "status";
          sd = "!git s && git d";
          sh = "show --patch-with-stat";
          shove = "git push --force-with-lease";
          stash-all = "stash --all";
          unstage = "restore --staged .";
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
          dark = true;
          features = "decorations unobtrusive-line-numbers";
          line-numbers = true;
          navigate = true;
          true-color = "always";
          side-by-side = true;
          file-style = "yellow";
          paging = "always";
          hyperlinks = true;
          # TODO: fix
          # https://dandavison.github.io/delta/hyperlinks.html
          # Something along the lines of https://github.com/`git remote get-url origin | some-filter`/`git branch -r --points-at COMMIT || COMMIT/{file}L{line}`
          # hyperlinks-file-link-format = "https://github.com/{path}:{line}";
          decorations = {
            commit-decoration-style = "bold yellow box ul";
            file-decoration-style = "none";
            file-style = "bold yellow ul";
          };
          unobtrusive-line-numbers = {
            line-numbers = true;
            line-numbers-left-format = "{nm:>4}┊";
            line-numbers-right-format = "{np:>4}│";
          };
        };
      };
      extraConfig = {
        core = {
          # configured by delta.enable=true and
          # ov.enable=true
        };
        branch.sort = "-committerdate";
        column.ui = "auto";
        fetch.writeCommitGraph = true;
        diff = {
          colorMoved = "default";
          # pair lockfiles to come after their source file
          # requires that these file types come first, but that is okay for me
          orderFile =
            builtins.toFile "gitorderfile.conf" # gitignore
              ''
                # git lets you specify the order of the files in all commands
                # by setting up an order file! I use this to make it so all lock
                # files appear last fist specify every file can appear first then
                # lockfiles come after due to the glob matching, you have to
                # specify exact paths
                # * <- does not work, greedily matches everything
                package.json
                package-lock.json
                yarn.lock
                pnpm-lock.yaml

                flake.nix
                flake.lock
                # you could try to match every other file type other than lock
                # files, but that is not robust. There will always be new file
                # types and some files don't even have extensions. Due to this. I
                # will opt for at least ordering the locks after their source. I
                # also don't want to greedy match locks because I want the source
                # to be tightly tied to the lock. I don't want to have unexpected
                # files appearing between the source and generated lock. By
                # setting explicit lock paths for each source, they are tighly
                # paired.

                # * <- implied at end of file, no effect here
              '';
          # ${./gitorderfile.conf}" ;
        };
        # configured by delta.enable=true
        # delta = {
        #   navigate = true;
        #   line-numbers = true;
        #   true-color = "always";
        # };
        "includeIf \"gitdir:~/\"" = {
          path = "~/.config/git/config.default";
        };
        "includeIf \"gitdir:~/Work/\"" = {
          path = "~/.config/git/config.work";
        };
        init = {
          defaultBranch = "main";
        };
        interactive = {
          # configured by delta.enable=true
          # this is used for diff patches
          # diffFilter = "delta";
        };
        merge = {
          conflictstyle = "diff3";
        };
        # This is needed so programs like Fugitive will use delta
        # Set by ov
        # pager = {
        #   blame = "delta";
        #   diff = "delta --features ov-diff";
        #   log = "delta --features ov-log";
        #   reflog = "delta";
        #   show = "delta --pager='ov --header 3'";
        # };
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
        remote.origin.fetch = "+refs/pull/*/head:refs/remotes/origin/pr/*";
        rerere.enabled = true;
      };
    };

    home.file.".config/git/config.default".source = gitIniFmt.generate "config.default" {
      user.email = "github@xav.ie";
    };

    home.file.".config/git/config.work".source = gitIniFmt.generate "config.work" {
      user.email = "xavier@outsmartly.com";
    };
  };
}
