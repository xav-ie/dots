_: {
  config = {
    programs.bat = {
      enable = true;
      config = {
        theme = "ansi";
        pager = "moar -quit-if-one-screen";
        paging = "auto";
        style = "plain";
        wrap = "character";
      };
    };
    home.sessionVariables = {
      # causes bug if set. dont do it!
      BAT_PAGER = "";
      # TODO: somehow link moar
      PAGER = ''bat -p --pager=\"moar -quit-if-one-screen\" --terminal-width=$(expr $COLUMNS - 4)'';
    };
  };
}
