{
  deepfilternet,
  ffmpeg-full,
  stdenv,
  swift,
}:
# Polish Recording — SwiftUI front-end for the screen-recording cleanup
# workflow: denoise audio (DeepFilterNet 3) and re-encode to HEVC.
# ffmpeg-full: the default ffmpeg is built --disable-ladspa.
stdenv.mkDerivation {
  pname = "polish-recording";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  postPatch = ''
    substituteInPlace main.swift \
      --replace-fail @ffmpeg@ ${ffmpeg-full.bin}/bin/ffmpeg \
      --replace-fail @ffprobe@ ${ffmpeg-full.bin}/bin/ffprobe \
      --replace-fail @deepfilter@ ${deepfilternet}/lib/ladspa/libdeep_filter_ladspa.dylib
  '';
  buildPhase = ''
    runHook preBuild
    # Stamp SDK 26 in LC_BUILD_VERSION: AppKit picks the Liquid Glass design from
    # the linked SDK version, and nixpkgs' Swift 5.10 can only compile against 14.x.
    swiftc -parse-as-library -O main.swift -o polish-recording \
      -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker 26.0
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    app="$out/Applications/Polish Recording.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp AppIcon.icns "$app/Contents/Resources/"
    cp polish-recording "$app/Contents/MacOS/polish-recording"
    cat > "$app/Contents/Info.plist" <<'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>polish-recording</string>
      <key>CFBundleIconFile</key><string>AppIcon</string>
      <key>CFBundleIdentifier</key><string>com.x.polish-recording</string>
      <key>CFBundleName</key><string>Polish Recording</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1.0</string>
      <key>LSMinimumSystemVersion</key><string>14.0</string>
    </dict></plist>
    EOF
    mkdir -p $out/bin
    ln -s "$app/Contents/MacOS/polish-recording" $out/bin/polish-recording
    runHook postInstall
  '';
  meta.mainProgram = "polish-recording";
}
