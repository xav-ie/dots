# The caches arca hosts and the GitHub repo that pushes to each. Read by the
# atticd-ensure-caches oneshot (../hosts/_arca-body.nix) to create each cache, by
# `cachectl sync`/`list` to wire each repo's ATTIC_TOKEN, and by the common nix
# settings (../common.nix) to add each as a substituter so local builds pull from
# them. To add a project: add an entry with `key = null`, run `cachectl sync`
# (creates the cache on the box, then mints the repo's ATTIC_TOKEN), then read
# the cache's public signing key and fill `key` in:
#
#   curl -s https://cache.lalala.casa/_api/v1/cache-config/<name> | jq -r .public_key
#
# `key = null` means "declared, not yet provisioned": common.nix skips it as
# both a substituter and a trusted key. That bootstrap state has to exist —
# a placeholder string instead makes every local build that consults a
# substituter die with `invalid character in Base64 string: ''`, including the
# `nix build` that `cachectl sync` itself runs to deploy the box.
#
# The same key goes in each repo's nix-cache CI action (as the ATTIC_PUBLIC_KEY
# repo variable) for `extra-trusted-public-keys`.
[
  {
    name = "canada";
    repo = "xav-ie/canada";
    key = "canada:JLsKjnlZ/arNjPhqL8lj9RtSEgOo5ykB5fT5TIQdjCw=";
  }
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
