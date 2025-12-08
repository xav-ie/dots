{ pkgs, ... }:
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
              version = "0.11.3";
              src = pkgs.fetchFromGitHub {
                owner = "ollama";
                repo = "ollama";
                tag = "v0.11.3";
                hash = "sha256-FghgCtVQIxc9qB5vZZlblugk6HLnxoT8xanZK+N8qEc=";
                fetchSubmodules = true;
              };
              vendorHash = "sha256-SlaDsu001TUW+t9WRp7LqxUSQSGDF1Lqu9M1bgILoX4=";
            });
      };
    };
  };
}
