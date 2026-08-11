{
  flake.modules.homeManager.common =
    {
      config,
      gpgKeys,
      osConfig,
      pkgs,
      ...
    }:
    let
      gitIniFmt = pkgs.formats.gitIni { };

      # gpg that reports a tty only when its caller actually owns one.
      # services.gpg-agent.enableSshSupport exports GPG_TTY at login, and every
      # child inherits it — including agent/daemon processes whose stdio are
      # pipes. pinentry-auto routes on the resulting `OPTION ttyname=`, so those
      # callers made pinentry draw onto a terminal they do not own, overwriting
      # whatever TUI was there until the ~60s pinentry timeout.
      #
      # Unsetting GPG_TTY is not enough on its own: with no ttyname from the
      # client, gpg-agent falls back to its own startup tty (whichever client
      # last ran `updatestartuptty`), so the prompt still lands on an unrelated
      # pane. `--pinentry-mode cancel` closes that path — a cached passphrase
      # still signs, an uncached one fails immediately instead of hijacking
      # someone else's terminal.
      gpg-tty-aware =
        pkgs.writeShellScriptBin "gpg-tty-aware" # sh
          ''
            if [ -t 2 ]; then
              export GPG_TTY="$(readlink /proc/self/fd/2)"
              exec ${pkgs.gnupg}/bin/gpg "$@"
            fi
            unset GPG_TTY
            exec ${pkgs.gnupg}/bin/gpg --pinentry-mode cancel "$@"
          '';

      # Same idea for ssh: it has no GPG_TTY equivalent, so gpg-agent only
      # learns a tty from whichever client last called updatestartuptty, and
      # pinentry otherwise falls through to gnome3 and fails over SSH.
      #
      # Per invocation rather than at shell start: a one-shot at login would
      # pin the agent to whichever long-lived herdr pane started last. GPG_TTY
      # stays scoped to the one call so daemons don't inherit it.
      ssh-tty-aware =
        pkgs.writeShellScriptBin "ssh-tty-aware" # sh
          ''
            if [ -t 2 ]; then
              GPG_TTY="$(readlink /proc/self/fd/2)" \
                ${pkgs.gnupg}/bin/gpg-connect-agent updatestartuptty /bye \
                >/dev/null 2>&1 || true
            fi
            exec ${pkgs.openssh}/bin/ssh "$@"
          '';
    in
    {
      # Git config validation (canonical casing, case collisions) runs via
      # `nix flake check` — see modules/flake/checks/git-config.nix.
      config = {
        programs.git = {
          enable = true;
          ignores = [
            "**/.claude/settings.local.json"
            ".edit-hooks.json"
            ".devenv*"
            ".direnv"
            ".osgrep"
            ".osgrepignore"
            ".pi"
            ".pre-commit-config.yaml"
            "CLAUDE.md"
            "devenv.local.nix"
          ];
          settings = {
            user.name = "Xavier Ruiz";
            # user.email = defined below...
            advice.detachedHead = false;
            alias =
              let
                diffTweaks =
                  [
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
                  ]
                  |> builtins.concatStringsSep " ";
              in
              {
                # aliases are case-insensitive
                B = "checkout -B";
                blame-better = "blame -w -C -C -C";
                c = "commit";
                cam = "commit -am";
                chekcout = "checkout";
                cm = "commit -m";
                co = "checkout";
                d = "diff ${diffTweaks}";
                dc = "diff --cached ${diffTweaks}";
                delete-tag = ''!f() { git tag -d "$1" && git push origin :refs/tags/"$1"; }; f'';
                ds = "!git d && git s";
                graph =
                  let
                    columns =
                      [
                        "%C(bold blue)%h%Creset"
                        "%s"
                        "%C(bold green)%d%Creset"
                        "%C(blue)<%an>%Creset"
                        "%C(dim cyan)%cr"
                      ]
                      |> builtins.concatStringsSep " ";
                  in
                  "log --graph --pretty=tformat:'${columns}' --abbrev-commit --decorate";
                main = # sh
                  "!(git fetch && git fetch --tags && git checkout -B main origin/main)";
                p = "push";
                patch = "show --patch";
                pull-force = "!git fetch && git reset --hard origin/$(git branch --show-current)";
                rmc = "rm --cached";
                s = "status";
                sd = "!git s && git d";
                sh = "show --patch-with-stat";
                shove = "push --force-with-lease";
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
            core = {
              # configured by delta.enable=true and
              # ov.enable=true
            };
            branch.sort = "-committerdate";
            column.ui = "auto";
            fetch.writeCommitGraph = true;
            push.autoSetupRemote = true;
            diff = {
              colorMoved = "default";
              # pair lockfiles to come after their source file
              # requires that these file types come first, but that is okay for me
              orderFile =
                # gitignore
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
                  # setting explicit lock paths for each source, they are tightly
                  # paired.

                  # * <- implied at end of file, no effect here
                ''
                |> builtins.toFile "gitorderfile.conf";
              # ${./gitorderfile.conf}" ;
            };
            # configured by delta.enable=true
            # delta = {
            #   navigate = true;
            #   line-numbers = true;
            #   true-color = "always";
            # };
            gpg.program = "${gpg-tty-aware}/bin/gpg-tty-aware";
            core.sshCommand = "${ssh-tty-aware}/bin/ssh-tty-aware";
            gpg.ssh.allowedSignersFile = osConfig.sops.secrets."git/allowed_signers".path;
            "includeif \"gitdir:~/\"" = {
              path = "~/.config/git/config.default";
            };
            "includeif \"gitdir:~/Work/\"" = {
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
              # https://becca.ooo/blog/why-diff3-is-confusing/
              conflictStyle = if config.programs.mergiraf.enable then "diff3" else "zdiff3";
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
            # remote.origin.fetch = [
            #   # Normal branches - set up by default
            #   "+refs/heads/*:refs/remotes/origin/*"
            #   # PR head commits
            #   "+refs/pull/*/head:refs/remotes/origin/pull/*"
            #   # Merge PR commits, disabled because noisy, but might be useful in future
            #   # "+refs/pull/*/head:refs/remotes/origin/pr/*"
            # ];
            rerere.enabled = true;
          };

          signing = {
            # Set key by email below. This ensures signing key email matches git commit email.
            key = null;
            signByDefault = true;
          };
        };

        xdg.configFile."git/config.default".source = gitIniFmt.generate "config.default" {
          user = {
            inherit (config.programs.git.settings.user) name;
            inherit (gpgKeys.personal) email;
            signingKey = gpgKeys.personal.id;
          };
        };

        xdg.configFile."git/config.work".source = gitIniFmt.generate "config.work" {
          user = {
            inherit (config.programs.git.settings.user) name;
            inherit (gpgKeys.work) email;
            signingKey = gpgKeys.work.id;
          };
        };

        # Manage ~/.gitconfig to prevent manual edits from overriding home-manager config.
        # Git reads ~/.gitconfig before ~/.config/git/config, so any settings there
        # would take precedence over our conditional includes.
        home.file.".gitconfig".text = "";
      };
    };
}
