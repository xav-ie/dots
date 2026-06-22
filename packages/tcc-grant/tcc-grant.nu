def main [
  --service: string        # TCC service name (see map below)
  --bundle-id: string      # client value: a bundle identifier, or an absolute path when --client-type 1
  --db: string             # Path to the TCC database (system or user — caller routes by service)
  --client-type: int = 0   # 0 = bundle identifier, 1 = absolute path
  --app-path: string = ""  # optional .app bundle to derive a cdhash csreq from (REQUIRED for ad-hoc / nix-signed apps)
] {
  let service_key = match $service {
    # Media
    "Camera" => "kTCCServiceCamera"
    "Microphone" => "kTCCServiceMicrophone"
    "ScreenCapture" => "kTCCServiceScreenCapture"
    # Automation / input
    "Accessibility" => "kTCCServiceAccessibility"
    "AppleEvents" => "kTCCServiceAppleEvents"
    "InputMonitoring" => "kTCCServiceListenEvent"
    "PostEvent" => "kTCCServicePostEvent"
    "DeveloperTool" => "kTCCServiceDeveloperTool"
    # Data
    "AddressBook" => "kTCCServiceAddressBook"
    "Calendar" => "kTCCServiceCalendar"
    "Reminders" => "kTCCServiceReminders"
    "Photos" => "kTCCServicePhotos"
    # System
    "SpeechRecognition" => "kTCCServiceSpeechRecognition"
    "FullDiskAccess" => "kTCCServiceSystemPolicyAllFiles"
    "DownloadsFolder" => "kTCCServiceSystemPolicyDownloadsFolder"
    "DesktopFolder" => "kTCCServiceSystemPolicyDesktopFolder"
    "DocumentsFolder" => "kTCCServiceSystemPolicyDocumentsFolder"
    "Location" => "kTCCServiceLiverpool"
    "FocusStatus" => "kTCCServiceFocusStatus"
    _ => { error make { msg: $"Unknown service: ($service)" } }
  }

  # With --app-path, pin the binary's cdhash as the code requirement: tccd rejects
  # a no-csreq grant for an ad-hoc / nix-signed binary (no trusted anchor). This is
  # what System Settings stores. codesign isn't on the wrapper PATH (call it
  # absolutely) and prints to stderr.
  let csreq = if ($app_path | is-empty) {
    "NULL"
  } else {
    let info = (^/usr/bin/codesign -dvvv $app_path | complete)
    let cdhash = (
      $info.stderr | lines
      | where { |l| $l | str starts-with "CDHash=" }
      | get 0?
      | default ""
      | str replace "CDHash=" ""
      | str trim
      | str upcase
    )
    if ($cdhash | is-empty) {
      error make { msg: $"could not read CDHash from ($app_path) — is it signed?" }
    }
    # fade0c00 | total len 0x28 | cdhash match expr (sha1, 0x14 bytes) | <cdhash>
    $"X'FADE0C0000000028000000010000000800000014($cdhash)'"
  }

  let cur_auth = (
    sqlite3 $db $"SELECT auth_value FROM access WHERE service='($service_key)' AND client='($bundle_id)' AND client_type=($client_type);"
    | str trim
  )

  if ($app_path | is-empty) {
    # Signed app: don't clobber a prior allow (it may carry a stronger csreq).
    if $cur_auth == "2" {
      print $"✓ ($bundle_id) already has ($service)"
      return
    }
  } else {
    # Ad-hoc app: re-pin unless already allowed with our exact cdhash.
    let cur_csreq = (
      sqlite3 $db $"SELECT quote\(csreq\) FROM access WHERE service='($service_key)' AND client='($bundle_id)' AND client_type=($client_type);"
      | str trim
    )
    if ($cur_auth == "2" and $cur_csreq == $csreq) {
      print $"✓ ($bundle_id) ($service) up to date"
      return
    }
  }

  sqlite3 $db $"INSERT OR REPLACE INTO access \(service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags\) VALUES \('($service_key)', '($bundle_id)', ($client_type), 2, 4, 1, ($csreq), 0\);"
  print $"✓ Granted ($service) to ($bundle_id)"
}
