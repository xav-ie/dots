{ pkgs, ... }:
{
  programs.yt-dlp = {
    enable = true;
    package = pkgs.pkgs-bleeding.yt-dlp;
    settings = {
      # Use Firefox cookies for YouTube authentication (fixes 403 errors and enables Premium)
      cookies-from-browser = "firefox";
      # Use web client with main player JS variant (TV variant breaks Deno/Node n-challenge solver)
      extractor-args = "youtube:player_client=web;player_js_variant=main";
    };
  };
}
