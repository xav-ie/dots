{ pkgs }:
let
  python3Packages = pkgs.python313Packages;

  # nixpkgs curl-impersonate-chrome 1.2.0 doesn't support chrome142;
  # patch curl_cffi to default to chrome136 which is the latest supported
  curl-cffi-patched = python3Packages.curl-cffi.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace curl_cffi/requests/impersonate.py \
        --replace-fail '"chrome142"' '"chrome136"'
    '';
  });

  discord-protos = python3Packages.buildPythonPackage rec {
    pname = "discord-protos";
    version = "1.2.377";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/8b/ce/ae825c2a70ef0bdd07c49d7b2171d77204aa76592b6deb8d2bf10c3681da/discord_protos-${version}-py3-none-any.whl";
      hash = "sha256-jhmPWJuI142tFct6OV0swzGivorgYGDzvqAX7Fuzx5A=";
    };

    # mypy-protobuf is only used to generate the stubs, but the published wheel
    # declares it at runtime and pythonRuntimeDepsCheck enforces that.
    dependencies = with python3Packages; [
      mypy-protobuf
      protobuf
    ];
    pythonImportsCheck = [ "discord_protos" ];
  };

  discord-py-self = python3Packages.buildPythonPackage rec {
    pname = "discord.py-self";
    version = "2.1.0";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "dolfies";
      repo = "discord.py-self";
      rev = "v${version}";
      hash = "sha256-jVz3uGU+4E5Awbk6ZYAsXvEpClNHm2QN1RpBTIiQTpE=";
    };

    build-system = with python3Packages; [ setuptools ];

    dependencies = [
      python3Packages.aiohttp
      curl-cffi-patched
      python3Packages.tzlocal
      discord-protos
      python3Packages.audioop-lts
    ];

    # v2.1.0 pins discord-protos<1.0.0 but the protos package jumped to 1.2.x
    postPatch = ''
      substituteInPlace requirements.txt \
        --replace-fail "discord_protos<1.0.0" "discord_protos"
    '';

    doCheck = false;
    pythonImportsCheck = [ "discord" ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "discord-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = with python3Packages; [ hatchling ];

  dependencies = [
    discord-py-self
    python3Packages.fastmcp
    python3Packages.mcp
    python3Packages.pydantic
    python3Packages.python-dotenv
  ];

  doCheck = false;
  pythonImportsCheck = [ "discord_mcp" ];

  meta = {
    description = "Discord MCP server using discord.py-self for user-account accessibility";
    license = pkgs.lib.licenses.mit;
    mainProgram = "discord-mcp";
  };
}
