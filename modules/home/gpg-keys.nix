# Injects the commit-signing identities as a `gpgKeys` module arg, shared by
# gpg, git and jujutsu. Both halves are public — the address is on every commit
# and the key ID rides along in every signature.
{
  flake.modules.homeManager.common = {
    _module.args.gpgKeys = {
      personal = {
        email = "github@xav.ie";
        id = "5B9134A9E7E7F965";
      };
      work = {
        email = "xavier@outsmartly.com";
        id = "22420DD6C13E3EB7";
      };
    };
  };
}
