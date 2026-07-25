// hidewin — toggle capture-hidden apps on demand.
//
// The always-on hiding lives in the injected agent
// (modules/darwin/_dyld-inject/hide-windows): every allowlisted app
// launches with its windows excluded from screen capture. This CLI just
// broadcasts a distributed notification that flips a running app between
// hidden and visible; the in-process agent does the actual sharingType
// change (a cross-process set silently no-ops — verified).
//
// Target is a bundle id (the same ids in services.dyldInject.hideWindows
// .apps) or --all to broadcast to every allowlisted app.
//
//   hidewin show <bundle-id>     reveal it to screen capture
//   hidewin hide <bundle-id>     re-hide it
//   hidewin show --all           reveal everything
//   hidewin hide --all           re-hide everything (default state)

import Foundation

func usage() -> Never {
  print(
    """
    hidewin — toggle capture-hidden apps (Invisiwind for macOS)

      hidewin show <target>|--all    reveal to screen capture
      hidewin hide <target>|--all    exclude from screen capture

    Every app is hidden by default; this reveals/re-hides at runtime (the
    menubar app is usually easier). <target> is a bundle id (all instances
    of an app, e.g. com.apple.MobileSMS) or a pid (one instance — e.g. a
    single Firefox profile). --all broadcasts to every app.
    """)
  exit(0)
}

let args = Array(CommandLine.arguments.dropFirst())

// `hidewin panel [x]` — toggle the hidewin-bar dropdown. The sketchybar
// plugin calls this on click, passing the item's x so the panel opens under it.
if args.first == "panel" {
  let x = args.dropFirst().first  // item x in device pixels, or nil
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.x.hidewin.toggle-panel"), object: x, userInfo: nil,
    deliverImmediately: true)
  _ = CFRunLoopRunInMode(.defaultMode, 0.2, false)
  exit(0)
}

guard let verb = args.first, verb == "show" || verb == "hide" else { usage() }
guard let target = args.dropFirst().first else { usage() }

let name = Notification.Name("com.x.hidewin.\(verb)")
// object nil == broadcast to all; a distributed notification's object is
// delivered cross-process as a string (userInfo is not — don't use it).
let object: String? = (target == "--all") ? nil : target

DistributedNotificationCenter.default().postNotificationName(
  name, object: object, userInfo: nil, deliverImmediately: true)

// Give distnoted a moment to flush before this short-lived process exits.
_ = CFRunLoopRunInMode(.defaultMode, 0.2, false)

print("\(verb): \(object ?? "all apps")")
