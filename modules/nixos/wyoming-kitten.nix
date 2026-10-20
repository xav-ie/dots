{
  # Kitten TTS nano as Home Assistant's text to speech, on 127.0.0.1:10200.
  flake.modules.nixos.praesidium =
    { inputs, ... }:
    {
      imports = [ inputs.wyoming-kitten.nixosModules.default ];

      services.wyoming-kitten.enable = true;
    };
}
