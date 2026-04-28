# Vendored fastmcp 3.2.4 + the three transitive dependencies that
# nixpkgs doesn't ship yet (griffelib, uncalled-for, py-key-value-aio).
# Consumers (mcp-atlassian, discord-mcp, etc.) take `fastmcp` from
# this set instead of `python313Packages.fastmcp`.
{
  pkgs-bleeding,
}:
let
  python3Packages = pkgs-bleeding.python313Packages;
  inherit (python3Packages) buildPythonPackage fetchPypi;
in
rec {
  griffelib = buildPythonPackage rec {
    pname = "griffelib";
    version = "2.0.2";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-PPILO8Rw6Ddj/78jbgB2sSEbrBvGfeE9r0lGQPLecH4=";
    };

    build-system = with python3Packages; [
      hatchling
      pdm-backend
      uv-dynamic-versioning
    ];

    env.UV_DYNAMIC_VERSIONING_BYPASS = version;

    pythonImportsCheck = [ "griffe" ];
  };

  uncalled-for = buildPythonPackage rec {
    pname = "uncalled-for";
    version = "0.3.1";
    pyproject = true;

    src = fetchPypi {
      pname = "uncalled_for";
      inherit version;
      hash = "sha256-XkEqxnCPBLVr71hntdz2aQ685OtzFgWNnFB4dJK7S8o=";
    };

    build-system = with python3Packages; [
      hatchling
      hatch-vcs
    ];

    # hatch-vcs reads the version from git, which the sdist doesn't carry.
    env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

    pythonImportsCheck = [ "uncalled_for" ];
  };

  py-key-value-aio = buildPythonPackage rec {
    pname = "py-key-value-aio";
    version = "0.4.4";
    pyproject = true;

    src = fetchPypi {
      pname = "py_key_value_aio";
      inherit version;
      hash = "sha256-4wEuYkPtfMCbsFRXvU0DsbpcKxyocACWs5J9t5/7vlU=";
    };

    build-system = with python3Packages; [ uv-build ];

    # Upstream pins `uv_build<0.9.0` but nixpkgs ships 0.9.7; the
    # constraint is conservative, the build works fine on 0.9.x.
    postPatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail 'uv_build>=0.8.2,<0.9.0' 'uv_build>=0.8.2'
    '';

    # Base deps + the [filetree, keyring, memory] extras fastmcp asks
    # for. The package's pyproject exposes its module as `key_value`.
    dependencies = with python3Packages; [
      beartype
      typing-extensions
      aiofile
      anyio
      keyring
      cachetools
    ];

    pythonImportsCheck = [ "key_value" ];
  };

  fastmcp = python3Packages.fastmcp.overridePythonAttrs (_old: {
    version = "3.2.4";

    src = fetchPypi {
      pname = "fastmcp";
      version = "3.2.4";
      hash = "sha256-CD7LdbRKQWnn/A9jL5S3gb2w/4d8azW5h3y7Vm/U1NE=";
    };

    dependencies =
      with python3Packages;
      [
        authlib
        cyclopts
        exceptiongroup
        httpx
        jsonref
        jsonschema-path
        mcp
        openapi-pydantic
        opentelemetry-api
        packaging
        platformdirs
        pydantic
        pyperclip
        python-dotenv
        pyyaml
        rich
        uvicorn
        watchfiles
        websockets
      ]
      ++ pydantic.optional-dependencies.email
      ++ [
        griffelib
        uncalled-for
        py-key-value-aio
      ];

    # Disable upstream's huge test suite — we're not validating fastmcp
    # itself, just packaging it. (nixpkgs' definition has ~25 disabled
    # tests already; sdist may not even ship the test tree.)
    doCheck = false;
    pythonImportsCheck = [ "fastmcp" ];
  });
}
