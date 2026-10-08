{
  pkgs-bleeding,
  mcp-atlassian-src,
}:
let
  # mcp-atlassian caps fastmcp <4.0.0. python313Packages.fastmcp is 3.4.7;
  # python314Packages has already moved to the 4.x line.
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

  # Markdown-to-Confluence converter — not in nixpkgs. mcp-atlassian wants
  # >=0.6.0,<0.7.0; 0.6.2 is the release in that range whose dependency
  # bounds nixpkgs-bleeding satisfies unrelaxed (0.6.3+ want orjson >=3.12
  # and cattrs >=26.2).
  markdown-to-confluence = python3Packages.buildPythonPackage rec {
    pname = "markdown-to-confluence";
    version = "0.6.2";
    pyproject = true;

    src = python3Packages.fetchPypi {
      pname = "markdown_to_confluence";
      inherit version;
      hash = "sha256-FfROlA1fKJTD5Sr85R/BL46dPJujQe2XGvG9neNj2Mg=";
    };

    build-system = [
      python3Packages.setuptools
      python3Packages.wheel
    ];

    dependencies = with python3Packages; [
      cattrs
      lxml
      markdown
      orjson
      pathspec
      pymdown-extensions
      pyyaml
      requests
      truststore
    ];

    pythonImportsCheck = [ "md2conf" ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "mcp-atlassian";
  version = "0.23.1";
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
    anyio
    atlassian-python-api
    beautifulsoup4
    cachetools
    click
    fakeredis
    fastmcp
    httpx
    keyring
    markdown
    markdown-to-confluence
    markdownify
    mcp
    pydantic
    pysocks
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

  # fakeredis only backs fastmcp's docket task queue, which stays unstarted
  # because mcp-atlassian registers no task=True components; nixpkgs-bleeding's
  # 2.36.2 is past the declared <2.35.0 cap
  pythonRelaxDeps = [ "fakeredis" ];

  pythonImportsCheck = [ "mcp_atlassian" ];

  meta = {
    description = "MCP server for Atlassian Jira and Confluence";
    homepage = "https://github.com/sooperset/mcp-atlassian";
    license = pkgs-bleeding.lib.licenses.mit;
    mainProgram = "mcp-atlassian";
  };
}
