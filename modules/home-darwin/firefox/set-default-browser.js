// Usage: osascript -l JavaScript set-default-browser.js <bundle-id>
// Makes <bundle-id> the default http/https handler, unless it already is.
ObjC.import("AppKit");

function run([id]) {
  const ws = $.NSWorkspace.sharedWorkspace;
  const app = ws.URLForApplicationWithBundleIdentifier(id);
  if (app.isNil()) throw new Error(`no app registered for ${id}`);

  const cur = ws.URLForApplicationToOpenURL(
    $.NSURL.URLWithString("http://example.com"),
  );
  if (!cur.isNil() && $.NSBundle.bundleWithURL(cur).bundleIdentifier.js === id)
    return;

  for (const scheme of ["http", "https"])
    ws.setDefaultApplicationAtURLToOpenURLsWithSchemeCompletionHandler(
      app,
      scheme,
      () => {},
    );
  $.NSRunLoop.currentRunLoop.runUntilDate(
    $.NSDate.dateWithTimeIntervalSinceNow(5),
  );
}
