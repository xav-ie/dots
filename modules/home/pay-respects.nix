# pay-respects (`f`): suggest a correction for the previous failed command.
#
# The runtime-rules module — which lets pay-respects read rules from
# ~/.config/pay-respects/rules/*.toml at runtime instead of baking them into the
# binary at compile time — ships in nixpkgs' pay-respects as
# `_pay-respects-module-100-runtime-rules`, which core auto-discovers by the
# `_pay-respects-module-` name prefix. The one rule we ship corrects a mistyped
# `just` recipe.
{
  flake.modules.homeManager.common = {
    config = {
      programs.pay-respects.enable = true;

      # Read at runtime by the bundled module, so editing this rule (or dropping
      # sibling *.toml rules next to it) is a home-manager switch away —
      # pay-respects itself never recompiles.
      xdg.configFile."pay-respects/rules/just.toml".source = ./pay-respects-just.toml;
    };
  };
}
