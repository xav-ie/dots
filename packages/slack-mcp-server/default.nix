{
  lib,
  buildGoModule,
  fetchpatch,
  src,
}:
buildGoModule {
  pname = "slack-mcp-server";
  version = src.shortRev or src.rev or "unstable";

  inherit src;

  patches = [
    # PR #200: feat: add message edit and delete tools.
    # Upstream is still open as of 2026-04-29; remove once merged + released.
    (fetchpatch {
      url = "https://github.com/korotovsky/slack-mcp-server/pull/200.diff";
      hash = "sha256-5Uj8Z/OR2d5hOtG0nogclviLw+cvRs60vgxuLAxxZ/U=";
    })
  ];

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
