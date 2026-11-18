import AppKit
import Intents
import UserNotifications

// Native macOS notifications for `notify`, posted from inside an app bundle so
// they can carry a per-notification avatar (communication notifications via
// INSendMessageIntent) and run a command when clicked.
//
//   notifier post < payload.json   post one notification and exit
//   notifier                       resident agent (launchd): handles clicks,
//                                  sweeps expired notifications, runs the
//                                  --on-wake command on login, wake and unlock
//
// Payload: {title, body, icon?, group?, expireAt?, onClick?}
//   icon      absolute path to an image used as the sender avatar
//   expireAt  unix seconds; the agent removes the notification after it
//   onClick   argv run when the notification is clicked

struct Payload: Decodable {
  var title: String
  var body: String
  var icon: String?
  var group: String?
  var expireAt: Double?
  var onClick: [String]?
}

func run(_ argv: [String]) {
  guard let exe = argv.first else { return }
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  p.arguments = [exe] + argv.dropFirst()
  var env = ProcessInfo.processInfo.environment
  env["PATH"] = [
    "/etc/profiles/per-user/\(NSUserName())/bin", "/run/current-system/sw/bin",
    "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
  ].joined(separator: ":")
  p.environment = env
  do { try p.run() } catch {
    FileHandle.standardError.write("run \(argv): \(error)\n".data(using: .utf8)!)
  }
}

func sweep(_ center: UNUserNotificationCenter) {
  center.getDeliveredNotifications { ns in
    let now = Date().timeIntervalSince1970
    let stale = ns.filter { n in
      guard let at = n.request.content.userInfo["expireAt"] as? Double else { return false }
      return at <= now
    }.map(\.request.identifier)
    if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
  }
}

func post(_ payload: Payload) async throws {
  let center = UNUserNotificationCenter.current()
  let granted = try await center.requestAuthorization(options: [.alert, .sound])
  guard granted else {
    throw NSError(
      domain: "notifier", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "notifications not allowed"])
  }

  let content = UNMutableNotificationContent()
  content.title = payload.title
  content.body = payload.body
  content.sound = .default
  if let g = payload.group { content.threadIdentifier = g }
  var info: [String: Any] = [:]
  if let e = payload.expireAt { info["expireAt"] = e }
  if let c = payload.onClick { info["onClick"] = c }
  content.userInfo = info

  var final: UNNotificationContent = content
  if let icon = payload.icon, FileManager.default.fileExists(atPath: icon) {
    let image = INImage(url: URL(fileURLWithPath: icon))
    let handle = INPersonHandle(value: icon, type: .unknown)
    let sender = INPerson(
      personHandle: handle, nameComponents: nil, displayName: payload.title, image: image,
      contactIdentifier: nil, customIdentifier: icon)
    let intent = INSendMessageIntent(
      recipients: nil, outgoingMessageType: .outgoingMessageText, content: payload.body,
      speakableGroupName: nil, conversationIdentifier: payload.group ?? icon, serviceName: nil,
      sender: sender, attachments: nil)
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    try? await interaction.donate()
    do { final = try content.updating(from: intent) } catch {
      FileHandle.standardError.write("avatar: \(error)\n".data(using: .utf8)!)
    }
  }
  try await center.add(
    UNNotificationRequest(identifier: UUID().uuidString, content: final, trigger: nil))
  sweep(center)
}

final class Agent: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let wakeCommand: [String]?
  var lastWake = Date.distantPast
  init(wakeCommand: [String]?) { self.wakeCommand = wakeCommand }

  // One wake raises didWake, screensDidWake and screenIsUnlocked in a burst;
  // run the command once per burst.
  func woke() {
    guard let wake = wakeCommand, Date().timeIntervalSince(lastWake) > 30 else { return }
    lastWake = Date()
    run(wake)
  }

  func applicationDidFinishLaunching(_ note: Notification) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    sweep(center)
    Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in sweep(center) }
    guard wakeCommand != nil else { return }
    woke()
    let ws = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.woke() }
    }
    DistributedNotificationCenter.default().addObserver(
      forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
    ) { [weak self] _ in self?.woke() }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler done: @escaping () -> Void
  ) {
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let argv = response.notification.request.content.userInfo["onClick"] as? [String]
    {
      run(argv)
    }
    done()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    done([.banner, .list, .sound])
  }
}

// Notification permission and click delivery go through LaunchServices, which
// only knows bundles it has registered; each build lands at a new store path.
LSRegisterURL(Bundle.main.bundleURL as CFURL, true)

let args = CommandLine.arguments.dropFirst()
if args.first == "post" {
  let data = FileHandle.standardInput.readDataToEndOfFile()
  Task {
    do {
      try await post(JSONDecoder().decode(Payload.self, from: data))
      exit(0)
    } catch {
      FileHandle.standardError.write("notifier: \(error)\n".data(using: .utf8)!)
      exit(1)
    }
  }
  RunLoop.main.run()
} else {
  // `notifier [--on-wake cmd args...]`
  let wake = args.first == "--on-wake" ? Array(args.dropFirst()) : nil
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let agent = Agent(wakeCommand: wake?.isEmpty == false ? wake : nil)
  app.delegate = agent
  app.run()
}
