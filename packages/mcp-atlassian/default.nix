{
  pkgs-bleeding,
  mcp-atlassian-src,
}:
let
  # Use Python 3.13 — python314Packages.fastmcp is broken in nixpkgs
  # due to py-key-value-aio pulling in aioboto3 → moto → cfn-lint →
  # aws-sam-translator which doesn't support 3.14
  python3Packages = pkgs-bleeding.python313Packages;

  # Type stubs for cachetools — not in nixpkgs.
  # Must use wheel because the sdist has a hyphenated package-data key
  # ("cachetools-stubs") that newer setuptools rejects.
  types-cachetools = python3Packages.buildPythonPackage {
    pname = "types-cachetools";
    version = "6.2.0.20260317";
    format = "wheel";

    src = pkgs-bleeding.fetchurl {
      url = "https://files.pythonhosted.org/packages/17/9a/b00b23054934c4d569c19f7278c4fb32746cd36a64a175a216d3073a4713/types_cachetools-6.2.0.20260317-py3-none-any.whl";
      hash = "sha256-kvqbxQ5GKeMfymfOs/sd5xeR4xT6FsCg0nKHJNwiLIs=";
    };
  };

  # Markdown-to-Confluence converter — not in nixpkgs
  markdown-to-confluence = python3Packages.buildPythonPackage rec {
    pname = "markdown-to-confluence";
    version = "0.3.5";
    pyproject = true;

    src = python3Packages.fetchPypi {
      pname = "markdown_to_confluence";
      inherit version;
      hash = "sha256-QwmvYlaC9tMA4ReZK4fmRZqK5rZT3uL5Empnis8Hbws=";
    };

    build-system = [
      python3Packages.setuptools
      python3Packages.wheel
    ];

    dependencies = with python3Packages; [
      lxml
      types-lxml
      markdown
      types-markdown
      pymdown-extensions
      pyyaml
      types-pyyaml
      requests
      types-requests
    ];

    pythonImportsCheck = [ "md2conf" ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "mcp-atlassian";
  version = "0.21.0";
  pyproject = true;

  src = mcp-atlassian-src;

  # hatchling + uv-dynamic-versioning needs a git repo for version;
  # bypass it since we know the version from the flake input tag
  env.UV_DYNAMIC_VERSIONING_BYPASS = version;

  build-system = with python3Packages; [
    hatchling
    uv-dynamic-versioning
  ];

  dependencies = with python3Packages; [
    atlassian-python-api
    beautifulsoup4
    cachetools
    click
    fastmcp
    httpx
    keyring
    markdown
    markdown-to-confluence
    markdownify
    mcp
    pydantic
    python-dateutil
    python-dotenv
    requests
    starlette
    thefuzz
    trio
    truststore
    types-cachetools
    types-python-dateutil
    unidecode
    urllib3
    uvicorn
  ];

  # No tests in the source tree without fixtures
  doCheck = false;

  # nixpkgs-bleeding has urllib3 2.6.0 but mcp-atlassian wants >=2.6.3;
  # the difference is trivial bugfixes, safe to relax
  pythonRelaxDeps = [ "urllib3" ];

  pythonImportsCheck = [ "mcp_atlassian" ];

  meta = {
    description = "MCP server for Atlassian Jira and Confluence";
    homepage = "https://github.com/sooperset/mcp-atlassian";
    license = pkgs-bleeding.lib.licenses.mit;
    mainProgram = "mcp-atlassian";
  };
}
