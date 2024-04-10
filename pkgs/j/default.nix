{ writeShellApplication, go-jira }:
writeShellApplication {
  name = "j";
  runtimeInputs = [ go-jira ];
  text = ''
    git branch --show-current | head -c 7 | xargs jira
  '';
}
