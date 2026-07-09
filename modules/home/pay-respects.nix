# pay-respects (`f`): suggest a correction for the previous failed command.
#
# nixpkgs builds only pay-respects' `core` workspace member, so the runtime-rules
# module — which lets pay-respects read rules from ~/.config/pay-respects/rules/
# *.toml at runtime instead of baking them into the binary at compile time —
# isn't packaged. We build that one member here (reusing core's pinned src +
# vendored deps, so it tracks nixpkgs' pay-respects bumps) and put it on PATH,
# where core auto-discovers it by the `_pay-respects-module-` name prefix (no
# _PR_LIB needed). The one rule we ship corrects a mistyped `just` recipe.
{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      config = {
        programs.pay-respects.enable = true;

        home.packages = [
          (pkgs.pay-respects.overrideAttrs (old: {
            pname = "pay-respects-module-runtime-rules";
            cargoBuildFlags = [
              "--package"
              "pay-respects-module-runtime-rules"
            ];
            cargoTestFlags = [
              "--package"
              "pay-respects-module-runtime-rules"
            ];
            # versionCheckHook greps the output for core's version/binary; this
            # member has its own version and a differently-named binary.
            doInstallCheck = false;
            meta = old.meta // {
              mainProgram = "_pay-respects-module-100-runtime-rules";
            };
          }))
        ];

        # Read at runtime by the module above, so editing this rule (or dropping
        # sibling *.toml rules next to it) is a home-manager switch away —
        # pay-respects itself never recompiles.
        xdg.configFile."pay-respects/rules/just.toml".source = ./pay-respects-just.toml;
      };
    };
}
