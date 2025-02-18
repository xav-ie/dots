_: {
  config = {
    programs.atuin = {
      enable = true;
      daemon.enable = true;
      enableZshIntegration = false;
      # https://docs.atuin.sh/configuration/config
      settings = {
        style = "compact";
        show_tabs = false;
        workspaces = true;
      };
    };
  };
}
