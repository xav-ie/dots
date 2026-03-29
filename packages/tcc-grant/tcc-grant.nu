def main [
  --service: string   # TCC service name
  --bundle-id: string # App bundle identifier
  --db: string        # Path to TCC database
] {
  let service_key = match $service {
    # Media
    "Camera" => "kTCCServiceCamera"
    "Microphone" => "kTCCServiceMicrophone"
    "ScreenCapture" => "kTCCServiceScreenCapture"
    # Automation
    "Accessibility" => "kTCCServiceAccessibility"
    "AppleEvents" => "kTCCServiceAppleEvents"
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

  # Check if permission already exists with auth_value=2 (allowed)
  let existing = (
    sqlite3 $db $"SELECT auth_value FROM access WHERE service='($service_key)' AND client='($bundle_id)';"
    | str trim
  )

  if $existing == "2" {
    print $"✓ ($bundle_id) already has ($service) permission"
    return
  }

  # Insert or replace permission
  sqlite3 $db $"INSERT OR REPLACE INTO access \(service, client, client_type, auth_value, auth_reason, auth_version, flags\) VALUES \('($service_key)', '($bundle_id)', 0, 2, 3, 1, 0\);"
  print $"✓ Granted ($service) to ($bundle_id)"
}
