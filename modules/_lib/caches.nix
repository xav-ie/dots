# The caches arca hosts and the GitHub repo that pushes to each. Read by the
# atticd-ensure-caches oneshot (../hosts/_arca-body.nix) to create each cache and
# by `cachectl sync`/`list` to wire each repo's ATTIC_TOKEN. To add a project:
# add a line, then `cachectl deploy` (creates the cache) and `cachectl sync`.
[
  {
    name = "browser-session-mcp";
    repo = "xav-ie/browser-session-mcp";
  }
  {
    name = "xnixvim";
    repo = "xav-ie/xnixvim";
  }
]
