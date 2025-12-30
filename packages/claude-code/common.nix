{
  lib,
  stdenv,
  socat,
  bubblewrap,
}:
{
  # Dependencies needed on Linux for sandboxing
  linuxDeps = [
    socat
    bubblewrap
  ];

  # Common wrapper arguments for wrapProgram
  wrapperArgs = lib.concatStringsSep " " [
    "--set DISABLE_AUTOUPDATER 1"
    "--set ENABLE_TOOL_SEARCH true"
    "--set ENABLE_EXPERIMENTAL_MCP_CLI false"
    (lib.optionalString stdenv.isLinux "--prefix PATH : ${lib.makeBinPath [ socat bubblewrap ]}")
  ];

  # Shared meta attributes
  meta =
    description:
    with lib;
    {
      inherit description;
      homepage = "https://claude.ai";
      license = licenses.unfree;
      maintainers = [ ];
      mainProgram = "claude";
    };
}
