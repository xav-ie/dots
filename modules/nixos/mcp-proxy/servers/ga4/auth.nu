# Mint the Google OAuth refresh token the ga4 MCP server (analytics-mcp) runs
# on and print it, with the client id/secret, for you to store in sops.
#
# Same oauth2l quirks as ../gtm/auth.nu: a cache hit returns an access token
# with no refresh token (so caching is off — every run is a real consent
# flow), and the consent prompt shares stdout with the result, whose last line
# is an authorized_user JSON blob rather than the bare token.
#
# Takes the OAuth *desktop* client JSON downloaded from the GCP console — the
# same client works across MCP servers; only the scopes differ.
def main [
  creds: string # path to the OAuth desktop client JSON
] {
  let creds = $creds | path expand
  if not ($creds | path exists) {
    error make {msg: $"($creds) does not exist"}
  }

  let client = open $creds | get installed? | default null
  if $client == null {
    error make {msg: $"($creds) is not a desktop OAuth client \(no `installed` key\). Create the client with type 'Desktop app'."}
  }

  # Read-only: analytics-mcp only requests the edit scope with --allow-write,
  # which the mcp-proxy deployment never passes.
  let scopes = "https://www.googleapis.com/auth/analytics.readonly"

  print "A browser window will open for consent — pick the Google account with GA4 access"
  print "(starhoney: analytics@outsmartly.com; RBX G-5LNX9PYYBY needs that account added as Viewer first)."
  let out = (
    oauth2l fetch --credentials $creds --scope $scopes --cache "" --output_format refresh_token
    | lines
    | each {|l| print $l; $l | str trim }
    | where {|l| $l | is-not-empty }
  )

  # `{"client_id":…,"client_secret":…,"refresh_token":…,"type":"authorized_user"}`,
  # or the bare token on oauth2l versions that print one.
  let last = $out | last
  let token = (
    try {
      $last | from json | get refresh_token
    } catch { $last }
  )
  if not ($token | str starts-with "1//") {
    error make {msg: $"oauth2l printed no refresh token — last line was: ($last)"}
  }

  if (input $"Delete ($creds)? [y/N] " | str trim) =~ '(?i)^y(es)?$' {
    rm $creds
    print $"Deleted ($creds)."
  }

  print ""
  print "Run this from the dots repo root, then `just system`:"
  print ""
  print (
    [
      [client_id $client.client_id]
      [client_secret $client.client_secret]
      [refresh_token $token]
    ]
    | each {|pair| $"  sudo sops set secrets/main.yaml '[\"ga4\"][\"($pair.0)\"]' '\"($pair.1)\"'" }
    | str join "\n"
  )
}
