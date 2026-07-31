# Mint the Google OAuth refresh token the self-hosted GTM MCP server runs on and
# print it, with the client id/secret, for you to store in sops.
#
# Takes the OAuth *desktop* client JSON downloaded from the GCP console. Two
# oauth2l quirks handled here: a cache hit returns an access token with no
# refresh token (so caching is off — every run is a real consent flow), and the
# consent prompt shares stdout with the result, whose last line is an
# authorized_user JSON blob rather than the bare token.
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

  # Full GTM API surface: read, edit containers + versions, publish, delete,
  # manage accounts + users.
  let scopes = [
    tagmanager.readonly
    tagmanager.edit.containers
    tagmanager.edit.containerversions
    tagmanager.publish
    tagmanager.delete.containers
    tagmanager.manage.accounts
    tagmanager.manage.users
  ] | each {|s| $"https://www.googleapis.com/auth/($s)" } | str join ","

  print "A browser window will open for consent — pick the Google account that owns the GTM containers."
  let out = (
    oauth2l fetch --credentials $creds --scope $scopes --cache "" --output_format refresh_token
    | lines
    | each {|l| print $l; $l | str trim }
    | where {|l| $l | is-not-empty }
  )

  # `{"client_id":…,"refresh_token":…,"type":"authorized_user"}`, or the bare
  # token on oauth2l versions that print one.
  let last = $out | last
  let token = (
    try {
      $last | from json | get refresh_token
    } catch { $last }
  )
  if not ($token | str starts-with "1//") {
    error make {msg: $"oauth2l printed no refresh token — last line was: ($last)"}
  }

  # Regex, not `str downcase`/`str lowercase`: the name differs across the nu
  # versions this is built against.
  if (input $"Delete ($creds)? [y/N] " | str trim) =~ '(?i)^y(es)?$' {
    rm $creds
    print $"Deleted ($creds)."
  }

  print ""
  print "Run this from the dots repo root, then `just`:"
  print ""
  print (
    [
      [client_id $client.client_id]
      [client_secret $client.client_secret]
      [refresh_token $token]
    ]
    | each {|pair| $"  sudo sops set secrets/main.yaml '[\"gtm\"][\"($pair.0)\"]' '\"($pair.1)\"'" }
    | str join "\n"
  )
}
