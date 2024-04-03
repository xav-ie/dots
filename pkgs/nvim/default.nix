{ writeShellApplication, }:
writeShellApplication {
  name = "nvim";
  text = ''
    "$HOME"/Projects/xnixvim/result/bin/nvim "$@"
  '';
}
