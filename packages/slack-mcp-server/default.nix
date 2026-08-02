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
    # Still open upstream; remove once merged + released. A `pull/N.diff` URL
    # renders the PR head, so it is not content-stable — expect to re-pin this
    # hash whenever the author pushes, or vendor the diff here instead.
    (fetchpatch {
      url = "https://github.com/korotovsky/slack-mcp-server/pull/200.diff";
      hash = "sha256-Ju7eTZv1p5McLdNZLBa7GTpQA9mjaw3cCY8hwC3jDWE=";
    })
  ];

  vendorHash = "sha256-3BS7E204pNNObWA7pDNTXPuMzEhq7zR7e6RBPp1Uzpw=";

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
