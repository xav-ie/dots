# `npx vibe-kanban` only downloads this artifact at runtime; fetch it directly
# so the version is pinned. Bump: BINARY_TAG from the npm package's bin/cli.js,
# sha256 from https://npm-cdn.vibekanban.com/binaries/<tag>/manifest.json.
{
  fetchurl,
  stdenvNoCC,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "vibe-kanban";
  version = "0.1.44";

  src = fetchurl {
    url = "https://npm-cdn.vibekanban.com/binaries/v0.1.44-20260424091429/linux-x64/vibe-kanban.zip";
    hash = "sha256-CD8V8CenBSkWhS9AYQ2zSwIffndJWTYjrD9noJBEems=";
  };

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 vibe-kanban $out/bin/vibe-kanban
    runHook postInstall
  '';

  meta = {
    description = "Kanban board for orchestrating coding agents across git worktrees";
    homepage = "https://github.com/BloopAI/vibe-kanban";
    mainProgram = "vibe-kanban";
    platforms = [ "x86_64-linux" ];
  };
}
