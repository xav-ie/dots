def main [
  --service: string        # TCC service name (see map below)
  --bundle-id: string      # client value: a bundle identifier, or an absolute path when --client-type 1
  --db: string             # Path to the TCC database (system or user — caller routes by service)
  --client-type: int = 0   # 0 = bundle identifier, 1 = absolute path
  --app-path: string = ""        # optional .app bundle to derive a cdhash csreq from (for ad-hoc / nix-signed apps)
  --designated-from: string = "" # .app whose current designated requirement is read + pinned as the csreq (re-signed apps); takes precedence over --app-path
] {
  let service_key = match $service {
    Camera => "kTCCServiceCamera"
    Microphone => "kTCCServiceMicrophone"
    ScreenCapture => "kTCCServiceScreenCapture"
    Accessibility => "kTCCServiceAccessibility"
    AppleEvents => "kTCCServiceAppleEvents"
    InputMonitoring => "kTCCServiceListenEvent"
    PostEvent => "kTCCServicePostEvent"
    DeveloperTool => "kTCCServiceDeveloperTool"
    AddressBook => "kTCCServiceAddressBook"
    Calendar => "kTCCServiceCalendar"
    Reminders => "kTCCServiceReminders"
    Photos => "kTCCServicePhotos"
    SpeechRecognition => "kTCCServiceSpeechRecognition"
    FullDiskAccess => "kTCCServiceSystemPolicyAllFiles"
    DownloadsFolder => "kTCCServiceSystemPolicyDownloadsFolder"
    DesktopFolder => "kTCCServiceSystemPolicyDesktopFolder"
    DocumentsFolder => "kTCCServiceSystemPolicyDocumentsFolder"
    Location => "kTCCServiceLiverpool"
    FocusStatus => "kTCCServiceFocusStatus"
    _ => {
      # Media
      # Automation / input
      # Data
      # System
      error make {msg: $"Unknown service: ($service)"}
    }
  }

  # csreq precedence: --designated-from (the bundle's own DR) > --app-path (cdhash) > NULL.
  #
  # --designated-from reads the bundle's current designated requirement (codesign
  # -d -r-) and pins it. Prefer this for re-signed apps: it auto-tracks whatever
  # Apple-anchored cert the bundle is signed with, so cert rotation needs no config
  # change. A cert-anchored requirement is also the only thing that works under
  # `amfi_get_out_of_my_way=1` — an ad-hoc cdhash pin is platform-flagged, and the
  # cdhash opcode is legacy-SHA-1 so it never matches a SHA-256-only signature.
  # /usr/bin/csreq compiles the requirement text from stdin (-r-); we hex-encode the
  # blob with xxd so it inlines as an X'..' literal (no readfile() dependency).
  let csreq = if ($designated_from | is-not-empty) {
    let info = (^/usr/bin/codesign -d -r- $designated_from | complete)
    let dr = (
      $"($info.stdout)\n($info.stderr)" | lines
      | where {|l| $l =~ 'designated => ' }
      | get 0?
      | default ""
      | str replace -r '^.*designated => ' ''
      | str trim
    )
    if ($dr | is-empty) {
      error make {msg: $"could not read designated requirement from ($designated_from)"}
    }
    let blob = $"/tmp/tcc-grant-($bundle_id)-($service_key).csreq"
    $dr | ^/usr/bin/csreq -r- -b $blob
    let hex = (
      ^/usr/bin/xxd -p $blob
      | lines
      | str join ""
      | str trim
      | str upcase
    )
    if ($hex | is-empty) {
      error make {msg: $"could not compile designated requirement: ($dr)"}
    }
    $"X'($hex)'"
  } else if ($app_path | is-empty) {
    "NULL"
  } else {
    let info = (^/usr/bin/codesign -dvvv $app_path | complete)
    let cdhash = (
      $info.stderr | lines
      | where {|l| $l | str starts-with "CDHash=" }
      | get 0?
      | default ""
      | str replace "CDHash=" ""
      | str trim
      | str upcase
    )
    if ($cdhash | is-empty) {
      error make {msg: $"could not read CDHash from ($app_path) — is it signed?"}
    }
    # fade0c00 | total len 0x28 | cdhash match expr (sha1, 0x14 bytes) | <cdhash>
    $"X'FADE0C0000000028000000010000000800000014($cdhash)'"
  }

  let cur_auth = (
    sqlite3 $db $"SELECT auth_value FROM access WHERE service='($service_key)' AND client='($bundle_id)' AND client_type=($client_type);"
    | str trim
  )

  if ($designated_from | is-empty) and ($app_path | is-empty) {
    # Bundle-id only: don't clobber a prior allow (it may carry a stronger csreq).
    if $cur_auth == "2" {
      print $"✓ ($bundle_id) already has ($service)"
      return
    }
  } else {
    # csreq-pinned (DR or cdhash): re-pin unless already allowed with our exact blob.
    let cur_csreq = (
      sqlite3 $db $"SELECT quote\(csreq\) FROM access WHERE service='($service_key)' AND client='($bundle_id)' AND client_type=($client_type);"
      | str trim
    )
    if $cur_auth == "2" and $cur_csreq == $csreq {
      print $"✓ ($bundle_id) ($service) up to date"
      return
    }
  }

  sqlite3 $db $"INSERT OR REPLACE INTO access \(service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags\) VALUES \('($service_key)', '($bundle_id)', ($client_type), 2, 4, 1, ($csreq), 0\);"
  print $"✓ Granted ($service) to ($bundle_id)"
}
