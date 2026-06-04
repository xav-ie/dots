# AGS (Astal) Notion-style calendar, bundled into a standalone gjs binary.
# Events are seeded in data.ts; user edits persist to SQLite via the sqlite3 CLI.
{
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  agsPackages,
  makeDesktopItem,
  copyDesktopItems,
  sqlite,
  libsoup_3,
  glib-networking,
  # System UI font family, threaded in from lib/fonts.nix so the calendar
  # tracks the same `sans` font as the rest of the GTK config.
  fontName,
  # System monospace font, used for dates/times/numbers (@MONO@ in style.scss).
  monoFont,
}:
stdenv.mkDerivation {
  name = "calendar";
  src = ./.;

  postPatch = ''
    # Generate the SCSS $colors map from the single palette source (palette.ts),
    # so the 24 colors are defined exactly once. Tolerant of prettier quoting the
    # key or not. Inserted at the `// @COLORS@` placeholder in style.scss.
    # Scope to the PALETTE block only — EVENT_COLORS further down also has
    # `hex: "#..."` lines that would otherwise collide as duplicate keys.
    {
      echo '$colors: ('
      sed -n '/export const PALETTE = {/,/} as const;/p' palette.ts \
        | grep -oE '"?[a-z][a-z-]*"?: "#[0-9a-f]{6}"' \
        | sed -E 's/^"?([a-z][a-z-]*)"?: "(#[0-9a-f]{6})"$/  "\1": \2,/'
      echo ');'
    } > colors.scss
    sed -i -e '/\/\/ @COLORS@/r colors.scss' -e '/\/\/ @COLORS@/d' style.scss
    rm colors.scss

    substituteInPlace style.scss \
      --replace-fail "@FONT@" "${fontName}" \
      --replace-fail "@MONO@" "${monoFont}"
  '';

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    agsPackages.default
    copyDesktopItems
  ];

  # On GI_TYPELIB_PATH at runtime via the gobject-introspection setup hook.
  buildInputs = [
    gjs
    agsPackages.io
    agsPackages.astal4
    # HTTP for the Google Calendar REST client + the OAuth loopback listener
    # (auth.ts / rest.ts, via ags/fetch + Soup.Server). glib-networking supplies
    # the GIO TLS module libsoup needs for https.
    libsoup_3
    glib-networking
  ];

  # Put sqlite3 (db.ts cache) on the app's PATH so it can spawn it at runtime,
  # and point GIO at glib-networking's TLS module for https.
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${sqlite}/bin)
    gappsWrapperArgs+=(--prefix GIO_EXTRA_MODULES : ${glib-networking}/lib/gio/modules)
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "calendar";
      desktopName = "Calendar";
      exec = "calendar";
      icon = "dots-calendar";
      comment = "Notion-style week calendar";
      categories = [
        "Office"
        "Calendar"
      ];
      startupWMClass = "io.Astal.calendar";
    })
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ags bundle app.ts $out/bin/calendar
    install -Dm644 icon.svg $out/share/icons/hicolor/scalable/apps/dots-calendar.svg
    install -Dm644 icons/gift-symbolic.svg $out/share/icons/hicolor/scalable/actions/gift-symbolic.svg

    # Pre-generate a tray/app icon per accent color (the calendar palette) so the
    # tray can swap icons when the in-app accent changes (theme.ts / Sidebar
    # picker). The glyph's accent is a single color (#eb5757; the tab darkening is
    # a black overlay), so each variant is one substitution. Names mirror
    # palette.ts and accentIcon(): dots-calendar-<name>. Same PALETTE-block grep
    # as the $colors generation above.
    icons_apps=$out/share/icons/hicolor/scalable/apps
    sed -n '/export const PALETTE = {/,/} as const;/p' palette.ts \
      | grep -oE '"?[a-z][a-z-]*"?: "#[0-9a-f]{6}"' \
      | sed -E 's/^"?([a-z][a-z-]*)"?: "(#[0-9a-f]{6})"$/\1 \2/' \
      | while read -r name hex; do
          sed "s/#eb5757/$hex/g" icon.svg >"$icons_apps/dots-calendar-$name.svg"
        done

    gtk-update-icon-cache --quiet --no-uptodate-check $out/share/icons/hicolor || true
    runHook postInstall
  '';
}
