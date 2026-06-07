# System font packages and fontconfig; enables Maple Mono typographic features
# and maps Arial / ui-sans-serif onto the configured sans-serif fallback chain.
{
  flake.modules.nixos.linux =
    {
      config,
      lib,
      fonts,
      ...
    }:
    let
      fontCfg = config.fonts.fontconfig;
    in
    {
      config.fonts = {
        inherit (fonts) packages;
        fontconfig = {
          enable = true;

          localConf = # xml
            ''
              <?xml version="1.0"?>
              <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:font.dtd">
              <fontconfig>
                <match target="font">
                  <description>Enable some typographic features of Maple Mono NF font, for all applications.</description>
                  <test name="family" compare="eq" ignore-blanks="true">
                    <string>${fonts.name "mono"}</string>
                  </test>
                  <edit name="fontfeatures" mode="append">
                  ${lib.concatStringsSep "\n    " (
                    map (feature: "  <string>${feature} on</string>") (fonts.features "mono")
                  )}
                  </edit>
                </match>
                <alias>
                  <description>Some websites do not respect lacking Arial, use font-sans as fallback</description>
                  <family>Arial</family>
                  <prefer>
                  ${lib.concatStringsSep "\n    " (
                    map (font: "  <family>${font}</family>") fontCfg.defaultFonts.sansSerif
                  )}
                  </prefer>
                </alias>
                <alias>
                  <description>Some websites do not respect sans-serif and demand a ui-sans-serif</description>
                  <family>ui-sans-serif</family>
                  <prefer>
                  ${lib.concatStringsSep "\n    " (
                    map (font: "  <family>${font}</family>") fontCfg.defaultFonts.sansSerif
                  )}
                  </prefer>
                </alias>
              </fontconfig>
            '';

          defaultFonts = {
            serif = [
              (fonts.name "serif")
              (fonts.name "cjk")
              (fonts.name "emoji")
            ];
            sansSerif = [
              (fonts.name "sans")
              (fonts.name "cjk")
              (fonts.name "emoji")
            ];
            monospace = [
              (fonts.name "mono")
              (fonts.name "cjk")
              (fonts.name "emoji")
            ];
            emoji = [ (fonts.name "emoji") ];
          };
        };
      };
    };
}
