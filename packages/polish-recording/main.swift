import AVKit
import AppKit
import SwiftUI

let ffmpegPath = "@ffmpeg@"
let ffprobePath = "@ffprobe@"
let deepFilterPlugin = "@deepfilter@"

enum Denoise: String, CaseIterable, Identifiable {
  case off = "Off"
  case light = "Light"
  case strong = "Strong"
  var id: Self { self }
  // DeepFilterNet 3 via LADSPA; c0 is its attenuation limit in dB (100 = unlimited).
  var filter: String? {
    let limit: Int
    switch self {
    case .off: return nil
    case .light: limit = 18
    case .strong: limit = 100
    }
    return "aresample=48000,ladspa=f=\(deepFilterPlugin):p=deep_filter_stereo:c=c0=\(limit)"
  }
}

func newestScreenRecording() -> URL? {
  let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
  let files =
    (try? FileManager.default.contentsOfDirectory(
      at: desktop, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
  return
    files
    .filter { $0.lastPathComponent.hasPrefix("Screen Recording") && $0.pathExtension == "mov" }
    .max {
      let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
      let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
      return (a ?? .distantPast) < (b ?? .distantPast)
    }
}

func bytes(_ url: URL) -> Int64 {
  Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
}

func formatBytes(_ n: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

func probeDuration(_ url: URL) -> Double {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: ffprobePath)
  p.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path]
  let out = Pipe()
  p.standardOutput = out
  try? p.run()
  p.waitUntilExit()
  return Double(
    String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

func probeHasAudio(_ url: URL) -> Bool {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: ffprobePath)
  p.arguments = [
    "-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0",
    url.path,
  ]
  let out = Pipe()
  p.standardOutput = out
  try? p.run()
  p.waitUntilExit()
  return !out.fileHandleForReading.readDataToEndOfFile().isEmpty
}

func probeAspect(_ url: URL) -> Double? {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: ffprobePath)
  p.arguments = [
    "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of",
    "csv=p=0:s=x", url.path,
  ]
  let out = Pipe()
  p.standardOutput = out
  try? p.run()
  p.waitUntilExit()
  let wh = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "x").compactMap { Double($0) }
  return wh.count == 2 && wh[1] > 0 ? wh[0] / wh[1] : nil
}

struct PlayerView: NSViewRepresentable {
  let player: AVPlayer
  func makeNSView(context: Context) -> AVPlayerView {
    let v = AVPlayerView()
    v.controlsStyle = .inline
    return v
  }
  func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}

final class Job: ObservableObject {
  @Published var progress: Double?
  @Published var error: String?
  private var process: Process?

  // DeepFilterNet's LADSPA plugin is real-time: when a frame takes longer than
  // its audio duration it pads silence and grows latency. Sharing the CPU with
  // x265 trips that, so denoising runs as its own audio-only pass first.
  func run(
    inputArgs: [String], denoise af: String?, args: [String], output out: URL,
    duration: Double, onDone: @escaping (URL) -> Void
  ) {
    progress = 0
    error = nil
    let encode = { (audio: [String], cleanup: URL?) in
      self.spawn(inputArgs + audio + args + [out.path], duration: duration, range: (0.1, 0.9)) {
        if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
        if $0 { onDone(out) } else { try? FileManager.default.removeItem(at: out) }
      }
    }
    guard let af else { return encode(["-map", "0:v", "-map", "0:a?"], nil) }
    let wav = FileManager.default.temporaryDirectory
      .appendingPathComponent("polish-audio-\(UUID().uuidString).wav")
    spawn(
      inputArgs + ["-vn", "-af", af, "-c:a", "pcm_f32le", wav.path], duration: duration,
      range: (0, 0.1)
    ) { ok in
      guard ok else {
        try? FileManager.default.removeItem(at: wav)
        return
      }
      encode(["-i", wav.path, "-map", "0:v", "-map", "1:a"], wav)
    }
  }

  private func spawn(
    _ args: [String], duration: Double, range: (Double, Double), done: @escaping (Bool) -> Void
  ) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: ffmpegPath)
    p.arguments =
      ["-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-y"] + args
    let stdout = Pipe()
    let stderr = Pipe()
    p.standardOutput = stdout
    p.standardError = stderr
    stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
      let text = String(decoding: h.availableData, as: UTF8.self)
      for line in text.split(separator: "\n") where line.hasPrefix("out_time_us=") {
        guard duration > 0, let us = Double(line.dropFirst("out_time_us=".count)) else { continue }
        let f = min(us / 1e6 / duration, 1)
        DispatchQueue.main.async { self?.progress = range.0 + f * (range.1 - range.0) }
      }
    }
    p.terminationHandler = { [weak self] p in
      stdout.fileHandleForReading.readabilityHandler = nil
      let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      DispatchQueue.main.async {
        guard let self else { return }
        let ok = p.terminationReason == .exit && p.terminationStatus == 0
        self.process = nil
        if !ok {
          self.progress = nil
          if p.terminationReason == .exit {
            self.error = err.isEmpty ? "ffmpeg failed" : err
          }
        } else if range.1 >= 1 {
          self.progress = nil
        }
        done(ok)
      }
    }
    do {
      try p.run()
      process = p
    } catch {
      progress = nil
      self.error = error.localizedDescription
    }
  }

  func cancel() { process?.terminate() }
}

struct ContentView: View {
  @AppStorage("denoise") private var denoise = Denoise.strong
  @AppStorage("crf") private var crf = 24.0
  @AppStorage("fps") private var fps = 60
  @AppStorage("halfSize") private var halfSize = false
  @AppStorage("openWhenDone") private var openWhenDone = true
  @AppStorage("clipSeconds") private var clipSeconds = 10

  @State private var input: URL?
  @State private var duration = 0.0
  @State private var hasAudio = false
  @State private var aspect = 16.0 / 10
  @State private var original: AVPlayer?
  @State private var after: AVPlayer?
  @State private var showAfter = false
  @State private var previewStart = 0.0
  @State private var output: URL?
  @StateObject private var exportJob = Job()
  @StateObject private var previewJob = Job()

  var body: some View {
    VStack(spacing: 0) {
      player
      VStack(alignment: .leading, spacing: 20) {
        transport
        controls
        footer
      }
      .padding(20)
    }
    .frame(width: 640)
    .fixedSize(horizontal: false, vertical: true)
    .navigationTitle(input?.lastPathComponent ?? "Polish Recording")
    .navigationSubtitle(
      input.map {
        "\(formatBytes(bytes($0))) · \(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))"
      } ?? "")
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first else { return false }
      load(url)
      return true
    }
    .toolbar {
      Button {
        load(newestScreenRecording())
      } label: {
        Label("Latest Recording", systemImage: "clock.arrow.circlepath")
      }
      .help("Load the newest screen recording on the Desktop")
      Button {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        if panel.runModal() == .OK { load(panel.url) }
      } label: {
        Label("Open…", systemImage: "folder")
      }
      .help("Choose a video")
    }
    .onAppear { load(newestScreenRecording()) }
  }

  @ViewBuilder var player: some View {
    ZStack {
      Color.black
      if let p = showAfter ? after : original {
        PlayerView(player: p)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "film").font(.system(size: 40))
          Text("Drop a recording here")
        }
        .foregroundStyle(.secondary)
      }
      if let p = previewJob.progress {
        VStack {
          ProgressView(value: p).frame(width: 200)
          Text("Rendering preview…").font(.caption)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
      }
    }
    .aspectRatio(aspect, contentMode: .fit)
  }

  var transport: some View {
    HStack {
      Picker("", selection: Binding(get: { showAfter }, set: setAfter)) {
        Text("Before").tag(false)
        Text("After").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .disabled(after == nil)
      Spacer()
      Menu {
        ForEach([5, 10, 30], id: \.self) { s in
          Button("\(s) seconds") { clipSeconds = s }
        }
      } label: {
        Label("Preview \(clipSeconds)s", systemImage: "play.fill")
      } primaryAction: {
        preview()
      }
      .fixedSize()
      .disabled(input == nil || previewJob.progress != nil)
      .help("Process a clip starting at the current playhead")
    }
  }

  var controls: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) {
      GridRow {
        Text("Noise reduction:").gridColumnAlignment(.trailing)
        Picker("", selection: $denoise) {
          ForEach(Denoise.allCases) { Text($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
      }
      GridRow {
        Text("Quality:")
        // CRF: lower = better quality, bigger file. Slider is inverted so right = better.
        Slider(value: Binding(get: { 50 - crf }, set: { crf = 50 - $0 }), in: 18...32, step: 1) {
          EmptyView()
        } minimumValueLabel: {
          Text("Smaller").foregroundStyle(.secondary)
        } maximumValueLabel: {
          Text("Better").foregroundStyle(.secondary)
        }
      }
      GridRow {
        Text("Frame rate:")
        HStack(spacing: 20) {
          Picker("", selection: $fps) {
            Text("Original").tag(0)
            Text("60 fps").tag(60)
            Text("30 fps").tag(30)
          }
          .labelsHidden()
          .fixedSize()
          Toggle("Half resolution", isOn: $halfSize)
        }
      }
    }
  }

  var footer: some View {
    HStack(spacing: 12) {
      if let p = exportJob.progress {
        ProgressView(value: p)
        Button("Cancel") { exportJob.cancel() }
      } else {
        if let output, let input {
          Label(
            "\(formatBytes(bytes(input))) → \(formatBytes(bytes(output)))",
            systemImage: "checkmark.circle.fill"
          )
          .foregroundStyle(.green)
          Spacer()
          Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
          Button("Trash Both") {
            try? FileManager.default.trashItem(at: input, resultingItemURL: nil)
            try? FileManager.default.trashItem(at: output, resultingItemURL: nil)
            load(newestScreenRecording())
          }
        } else {
          if let err = exportJob.error ?? previewJob.error {
            Text(err).foregroundStyle(.red).lineLimit(2).textSelection(.enabled)
          } else {
            Toggle("Open when done", isOn: $openWhenDone)
          }
          Spacer()
        }
        Button("Polish") { polish() }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
          .disabled(input == nil)
      }
    }
  }

  func load(_ url: URL?) {
    original?.pause()
    after?.pause()
    input = url
    original = url.map { AVPlayer(url: $0) }
    after = nil
    showAfter = false
    output = nil
    exportJob.error = nil
    previewJob.error = nil
    duration = url.map(probeDuration) ?? 0
    hasAudio = url.map(probeHasAudio) ?? false
    aspect = url.flatMap(probeAspect) ?? 16.0 / 10
  }

  func setAfter(_ v: Bool) {
    guard let o = original, let a = after, v != showAfter else { return }
    let (from, to) = v ? (o, a) : (a, o)
    let playing = from.rate > 0
    from.pause()
    let t =
      v ? max(0, o.currentTime().seconds - previewStart) : previewStart + a.currentTime().seconds
    to.seek(to: CMTime(seconds: t, preferredTimescale: 600))
    if playing { to.play() }
    showAfter = v
  }

  var encodeArgs: [String] {
    var args = ["-c:v", "libx265", "-x265-params", "log-level=error", "-crf", String(Int(crf))]
    args += ["-preset", "medium", "-tag:v", "hvc1", "-pix_fmt", "yuv420p"]
    if fps > 0 { args += ["-r", String(fps)] }
    if halfSize { args += ["-vf", "scale=iw/2:-2"] }
    return args + ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
  }

  func preview() {
    guard let input, let original else { return }
    let start = showAfter ? previewStart : max(0, original.currentTime().seconds)
    let len = min(Double(clipSeconds), max(duration - start, 1))
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent("polish-preview-\(UUID().uuidString).mp4")
    previewJob.run(
      inputArgs: ["-ss", String(start), "-t", String(len), "-i", input.path],
      denoise: hasAudio ? denoise.filter : nil, args: encodeArgs, output: out, duration: len
    ) { out in
      if let old = (after?.currentItem?.asset as? AVURLAsset)?.url {
        try? FileManager.default.removeItem(at: old)
      }
      original.pause()
      original.seek(to: CMTime(seconds: start, preferredTimescale: 600))
      previewStart = start
      after = AVPlayer(url: out)
      showAfter = true
      after?.play()
    }
  }

  func polish() {
    guard let input else { return }
    original?.pause()
    after?.pause()
    let out = input.deletingPathExtension().appendingPathExtension("polished.mp4")
    exportJob.run(
      inputArgs: ["-i", input.path], denoise: hasAudio ? denoise.filter : nil, args: encodeArgs,
      output: out, duration: duration
    ) { out in
      output = out
      if openWhenDone { NSWorkspace.shared.open(out) }
    }
  }
}

@main
struct PolishRecording: App {
  var body: some Scene {
    Window("Polish Recording", id: "main") { ContentView() }
      .windowResizability(.contentSize)
      .windowToolbarStyle(.unifiedCompact)
  }
}
