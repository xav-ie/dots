{ pkgs, ... }:
{
  programs.yt-dlp = {
    enable = true;
    package = pkgs.pkgs-bleeding.yt-dlp;
    settings = {
      # Use Firefox cookies for YouTube authentication (fixes 403 errors and enables Premium)
      cookies-from-browser = "firefox";
      # Workaround for YouTube 403 errors - use web_safari client with actual player JS
      extractor-args = "youtube:player_client=default,web_safari;player_js_version=actual";
    };
  };
}
