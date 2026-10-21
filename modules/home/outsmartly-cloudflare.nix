# wrangler in ~/Work keeps its own login, so it can be the Outsmartly Cloudflare
# account while wrangler elsewhere stays on the personal one. devenvs shells
# read OUTSMARTLY_WRANGLER_HOME and preload ~/Work/devenvs/lib/wrangler-home.cjs,
# which points only wrangler processes at that folder; ~/Work/.envrc does the
# same for repos without their own .envrc. `wrangler login` once inside ~/Work.
{
  flake.modules.homeManager.common = {
    home.sessionVariables.OUTSMARTLY_WRANGLER_HOME = "$HOME/.local/share/wrangler-outsmartly";
    home.file."Work/.envrc".text = # sh
      ''
        preload="$HOME/Work/devenvs/lib/wrangler-home.cjs"
        if [ -n "''${OUTSMARTLY_WRANGLER_HOME:-}" ] && [ -r "$preload" ]; then
          case "''${NODE_OPTIONS:-}" in
            *"$preload"*) ;;
            *) export NODE_OPTIONS="--require=$preload''${NODE_OPTIONS:+ $NODE_OPTIONS}" ;;
          esac
        fi
        unset preload
      '';
  };
}
