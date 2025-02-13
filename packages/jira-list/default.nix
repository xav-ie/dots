{
  writeShellApplication,
  go-jira,
  fzf,
  cache-command,
}:
writeShellApplication {
  name = "jira-list";
  runtimeInputs = [
    go-jira
    fzf
    cache-command
  ];
  # TODO: add action on select, add open-in-browser
  text = ''
    cache-command jira ls | sort | fzf --preview="echo {} | head -c 7 | xargs cache-command jira view" --tac
  '';
}
