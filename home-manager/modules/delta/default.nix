_: {
  config = {
    programs.delta = {
      # I think it might not be worth it to turn this off and try and set up
      # yourself. There is a lot of set up this one flag does
      enable = true;
      options = {
        enabledGitIntegration = true;
        # Set syntax-theme via BAT_THEME env var or use --light/--dark flags
        # Light themes: GitHub, "Monokai Extended Light", OneHalfLight, "Solarized (light)", gruvbox-light
        # Dark themes: Monokai Extended, base16, Dracula, Nord, etc.
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
  };
}
