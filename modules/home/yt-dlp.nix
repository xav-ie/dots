{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    {
      programs.yt-dlp = {
        enable = true;
        # pkgs-bleeding's yt-dlp pulls deno (rusty-v8) which sometimes fails
        # to build on macOS.  Stable pkgs.yt-dlp is plenty recent.
        package = pkgs.yt-dlp;
        settings = {
          # Use Firefox cookies for YouTube authentication (fixes 403 errors and enables Premium)
          cookies-from-browser = "firefox";
          # Use web client with main player JS variant (TV variant breaks Deno/Node n-challenge solver)
          extractor-args = "youtube:player_client=web;player_js_variant=main";
        };
      };
    };
}
