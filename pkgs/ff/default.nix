{ writeShellApplication, fzf, ripgrep }:
writeShellApplication {
  name = "ff";
  runtimeInputs = [ fzf ripgrep ];
  text = ''
    rg --files | fzf --preview 'bat --color=always {}' | xargs -r nvim
  '';
}
