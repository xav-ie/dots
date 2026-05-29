{
  lib,
  stdenvNoCC,
  electron,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  src,
}:
# Dedicated Notion Calendar desktop client. Notion ships no official Linux
# build, so this wraps calendar.notion.so in Electron. Wayland is picked up
# automatically via NIXOS_OZONE_WL, set in the Hyprland session.
stdenvNoCC.mkDerivation {
  pname = "notion-calendar";
  version = "1.0.4-unstable-${src.shortRev or src.rev or "git"}";

  inherit src;

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

  dontConfigure = true;
  dontBuild = true;

  desktopItems = [
    (makeDesktopItem {
      name = "notion-calendar";
      desktopName = "Notion Calendar";
      exec = "notion-calendar";
      icon = "notion-calendar";
      comment = "Notion Calendar desktop client";
      categories = [
        "Office"
        "Calendar"
      ];
      startupWMClass = "notion-calendar-electron";
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/notion-calendar
    cp index.js package.json $out/share/notion-calendar/
    install -Dm644 icon.png $out/share/icons/hicolor/512x512/apps/notion-calendar.png

    makeWrapper ${lib.getExe electron} $out/bin/notion-calendar \
      --add-flags $out/share/notion-calendar

    runHook postInstall
  '';

  meta = {
    description = "Dedicated Notion Calendar desktop client for Linux (Electron wrapper)";
    homepage = "https://github.com/czlabinger/notion-calendar-electron";
    license = lib.licenses.mit;
    mainProgram = "notion-calendar";
    platforms = lib.platforms.linux;
  };
}
