{
  inputs,
  pkgs,
  ...
}:
{
  config = {
    services = {
      ollama = {
        enable = true;
        package =
          if pkgs.stdenv.isDarwin then
            pkgs.pkgs-bleeding.ollama
          else
            pkgs.ollama.overrideAttrs (_oldAttrs: {
              version = "unstable-${inputs.ollama-src.shortRev}";
              src = inputs.ollama-src;
              vendorHash = "sha256-NM0vtue0MFrAJCjmpYJ/rPEDWBxWCzBrWDb0MVOhY+Q=";
            });
      };
    };
  };
}
