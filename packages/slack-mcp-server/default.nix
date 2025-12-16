{
  lib,
  buildGoModule,
  src,
}:
buildGoModule {
  pname = "slack-mcp-server";
  version = src.shortRev or src.rev or "unstable";

  inherit src;

  vendorHash = "sha256-CEg7OHriwCD1XM4lOCNcIPiMXnHuerramWp4//9roOo=";

  subPackages = [ "cmd/slack-mcp-server" ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Slack MCP Server for AI assistants";
    homepage = "https://github.com/korotovsky/slack-mcp-server";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "slack-mcp-server";
  };
}
