{
  flake.modules.homeManager.linux =
    # Daily auto-commit-and-push for the Notes repo. Stages everything
    # (tracked + untracked), commits with a dated message, and pushes. SSH auth
    # works headless because ~/.ssh/id_ed25519 is passphraseless and wired up as
    # the IdentityFile in ~/.ssh/config.
    {
      config,
      pkgs,
      ...
    }:
    let
      notesDir = "${config.home.homeDirectory}/Notes";

      notes-push = pkgs.writeShellApplication {
        name = "notes-push";
        runtimeInputs = [
          pkgs.git
          pkgs.openssh
        ];
        text = ''
          repo=${notesDir}
          cd "$repo"

          # Nothing to do if the working tree is clean.
          if git diff --quiet && git diff --cached --quiet && \
             [ -z "$(git status --porcelain)" ]; then
            echo "notes-push: clean tree, nothing to commit"
            exit 0
          fi

          git add -A
          git commit -m "chore(notes): daily sync $(date +%Y-%m-%d)"

          # Integrate remote changes first so the push isn't rejected; the commit
          # above means there's nothing to autostash, but it's cheap insurance.
          git pull --rebase --autostash
          git push
          echo "notes-push: pushed"
        '';
      };
    in
    {
      home.packages = [ notes-push ];

      services.scheduled.notes-push = {
        description = "Auto-commit and push the Notes repo";
        command = "${notes-push}/bin/notes-push";
        workingDirectory = notesDir;
        calendar = "daily";
        hour = 23;
        minute = 0;
      };
    };
}
