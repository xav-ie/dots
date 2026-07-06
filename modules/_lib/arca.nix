# arca host identity, shared by the NixOS host (../hosts/_arca-body.nix) and the
# terranix cloud config (../flake/_arca-infra.nix) so values can't drift. The R2
# endpoint is absent on purpose — it embeds the account id, so it's supplied at
# runtime via sops rather than committed to this public repo.
{
  # DNS-only A record → box IP; TLS via Let's Encrypt.
  domain = "cache.lalala.casa";
  acmeEmail = "cache.lalala.casa@xav.ie";
  cacheSubdomain = "cache";
  r2Bucket = "nix-cache";
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMW+HCZNdLZO3RVs9XCCw9iOeBprmfEfjTVsiuB81LOr";
}
