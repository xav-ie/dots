_: {
  config = {
    home.sessionVariables = {
      MANPAGER = "nvim +Man!";
      # This ensures man-width is not pre-cut before it reaches nvim. Nvim can do that.
      MANWIDTH = "999";
    };
  };
}
