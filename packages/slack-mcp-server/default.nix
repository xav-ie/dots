{
  lib,
  buildGoModule,
  src,
}:
buildGoModule {
  pname = "slack-mcp-server";
  version = src.shortRev or src.rev or "unstable";

  inherit src;

  vendorHash = "sha256-mR+UFQRi98OTCyNISy3e7QTGKusd8XhNW4iz57QvpZE=";

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
