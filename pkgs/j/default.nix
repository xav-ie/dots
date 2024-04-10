{ writeShellApplication, go-jira }:
writeShellApplication {
  # TODO: add option to pass in a project-ticket_number/ticket_number instead
  name = "j";
  runtimeInputs = [ go-jira ];
  text = ''
    git branch --show-current | head -c 7 | xargs jira
  '';
}
