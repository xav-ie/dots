{ lib, ... }:
{
  options = {
    defaultUser = lib.mkOption {
      type = lib.types.str;
      example = "x";
      default = "x";
      description = "The default username for various system configurations and services.";
    };
  };

  config = {
    defaultUser = "x";
  };
}
