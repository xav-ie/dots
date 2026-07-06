# The caches arca hosts and the GitHub repo that pushes to each. Read by the
# atticd-ensure-caches oneshot (../hosts/_arca-body.nix) to create each cache, by
# `cachectl sync`/`list` to wire each repo's ATTIC_TOKEN, and by the common nix
# settings (../common.nix) to add each as a substituter so local builds pull from
# them. To add a project: add an entry (name/repo/key), then `cachectl deploy`
# (creates the cache) and `cachectl sync`. The `key` is the cache's public
# signing key (`attic cache info <name>`), the same one each repo's nix-cache CI
# action wires as an `extra-trusted-public-keys`.
[
  {
    name = "browser-session-mcp";
    repo = "xav-ie/browser-session-mcp";
    key = "browser-session-mcp:4f8gtvt2/RI9gGFU3zAvDhMJO7jwNv3t06fy7ayaV3M=";
  }
  {
    name = "nuenv";
    repo = "xav-ie/nuenv";
    key = "nuenv:MyjRq6sJLzmfLzWbn/JN5BI9arB9L0SfgpydF56pGug=";
  }
  {
    name = "xnixvim";
    repo = "xav-ie/xnixvim";
    key = "xnixvim:9ZPNdLt+VqJRfOCmMQiB+goxckuVm0eiDGy18U21QCw=";
  }
]
