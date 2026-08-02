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
    # Upstream is still open as of 2026-08-02; remove once merged + released.
    #
    # NOTE: a `pull/N.diff` URL is NOT content-stable — it renders the PR's
    # current head, so any push or rebase by the author changes the bytes and
    # breaks this hash. That is what happened here: the pin was taken
    # 2026-04-29, the author pushed on 2026-07-14, and the next rebuild that
    # missed cache failed with a fixed-output hash mismatch. Expect to re-pin
    # whenever upstream touches the PR; if that gets tiresome, vendor the diff
    # into this directory instead.
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
