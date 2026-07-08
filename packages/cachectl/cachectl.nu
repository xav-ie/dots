# cachectl — operate the self-hosted Nix binary cache.
#
# The cache is `atticd` on the headless `arca` Hetzner VPS at
# https://cache.lalala.casa, blobs and OpenTofu state on Cloudflare R2. This CLI
# drives its lifecycle: provision the cloud, install/update NixOS, and mint
# per-project push/pull tokens.
#
# Admin SSH is tailnet-only, so `deploy`/`mint` reach arca at its Tailscale IP.
# Runs against the dots checkout ($env.DOTS, default ~/Projects/dots).

# ── helpers ─────────────────────────────────────────────────────────────────

# arca's admin SSH target, resolved from its Tailscale hostname (tailnet-only,
# and a reinstall hands arca a new tailnet IP).
def arca-ssh [] {
  $"root@(tailscale ip -4 arca | str trim)"
}

def dots-dir [] {
  $env.DOTS? | default $"($env.HOME)/Projects/dots"
}

# Decrypt the `arca-tofu` sops blob into a record of env vars for OpenTofu. sudo
# is only for the decrypt (the age master key is root-only). tofu's s3 backend
# wants AWS_ENDPOINT_URL_S3, so mirror it from the generic AWS_ENDPOINT_URL.
def tofu-env [] {
  let blob = (
    sudo SOPS_AGE_KEY_FILE=/etc/age/keys.txt
      sops -d --extract '["arca-tofu"]["env"]' $"(dots-dir)/secrets/main.yaml"
  )
  let vars = (
    $blob | lines | where {|l| ($l | str trim) != "" }
    | parse "{key}={value}"
    | reduce --fold {} {|it, acc| $acc | upsert $it.key $it.value }
  )
  if "AWS_ENDPOINT_URL" in $vars {
    $vars | upsert AWS_ENDPOINT_URL_S3 $vars.AWS_ENDPOINT_URL
  } else {
    $vars
  }
}

# Run terranix (OpenTofu) with `sub` = "" | ".plan" | ".destroy". State lives in
# R2, so the .terranix workdir is disposable; the committed provider lock is
# seeded in before init and any upgrade copied back out.
def run-infra [sub: string] {
  let dir = (dots-dir)
  let lock = $"($dir)/modules/flake/.terraform.lock.hcl"
  let wd = $"($dir)/.terranix/arca-infra"
  mkdir $wd
  cp $lock $"($wd)/.terraform.lock.hcl"
  with-env (tofu-env) {
    cd $"($dir)/.terranix"
    nix run $"($dir)#arca-infra($sub)"
  }
  cp $"($wd)/.terraform.lock.hcl" $lock
}

# Mint a 2-year push/pull token for `cache`, signed on the box by atticadm from
# the RS256 secret in the atticd service env. Stateless JWT scoped to this cache.
def mint-token [cache: string] {
  let remote = r#'
    set -euo pipefail
    set -a; . /run/secrets/atticd/env; set +a
    cache="$1"
    # -print -quit: find exits after the first hit itself, so it can't take a
    # SIGPIPE from `head` closing the pipe (which pipefail+set -e would abort on).
    adm=$(find /nix/store -maxdepth 3 -type f -name atticadm -print -quit)
    cfg=$(systemctl show atticd -p ExecStart | grep -oE "/nix/store/[^ ]*\.toml" | head -1)
    "$adm" -f "$cfg" make-token --sub "ci-$cache" --validity "2 years" --push "$cache" --pull "$cache"
  '#
  # str trim: drop atticadm's trailing newline so it can't land inside the GH
  # secret and break `Authorization: Bearer <token>`.
  $remote | ssh (arca-ssh) bash -s $cache | str trim
}

# The declared caches (name → repo pairs), single-sourced from the flake and
# shared with the box's atticd-ensure-caches oneshot. Cache names are validated
# to [a-z0-9-] — attic's own charset, and it blocks shell-metacharacter
# injection into the `ssh … bash -s $cache` in mint-token.
def declared-caches [] {
  let caches = nix eval --json --file $"(dots-dir)/modules/_lib/caches.nix" | from json
  for c in $caches {
    if not ($c.name =~ '^[a-z0-9-]+$') {
      error make {msg: $"invalid cache name '($c.name)': must match [a-z0-9-]"}
    }
  }
  $caches
}

# The public cache hostname (from the same _lib/arca.nix the host module uses).
def cache-domain [] {
  nix eval --raw --file $"(dots-dir)/modules/_lib/arca.nix" --apply 'a: a.domain'
}

# Is `name` a live public cache on the box? Probed over HTTP, no auth.
def cache-exists [name: string, domain: string] {
  try {
    http get $"https://($domain)/($name)/nix-cache-info" | ignore
    true
  } catch { false }
}

# Deploy the box (nixos-rebuild switch over the tailnet). Shared by `deploy` and
# by `sync` (which calls it when a declared cache isn't on the box yet).
def deploy-box [] {
  cd (dots-dir)
  nixos-rebuild switch --flake ".#arca" --target-host (arca-ssh) --use-substitutes
}

# ── commands ────────────────────────────────────────────────────────────────

def main [] {
  print "cachectl — operate the self-hosted Nix binary cache (atticd on arca)."
  print ""
  print "Commands:"
  print "  infra plan|apply|destroy   provision the cloud (Hetzner + Cloudflare) via terranix"
  print "  install <ip>               first-time NixOS install on a fresh box (nixos-anywhere)"
  print "  deploy                     push a config update to the box (config-only changes)"
  print "  sync                       deploy if needed, then install ATTIC_TOKEN on every repo"
  print "  list                       show declared caches vs reality (on box? token set?)"
  print ""
  print "Run 'cachectl <command> --help' for details."
}

# Provision / preview / tear down arca's cloud resources (Hetzner box + firewall,
# Cloudflare DNS + R2 bucket). State is backed by R2.
def "main infra" [
  action: string # plan | apply | destroy
] {
  let sub = match $action {
    plan => ".plan"
    apply => ""
    destroy => ".destroy"
    _ => (
      error make {msg: $"unknown action '($action)' — expected plan|apply|destroy"}
    )
  }
  run-infra $sub
}

# First-time install: turn a fresh Debian box at <ip> into NixOS via
# nixos-anywhere. Run once per box with the public IP from `cachectl infra apply`
# (Tailscale isn't up yet).
#
# A fresh install generates a new SSH host key, and arca decrypts secrets/arca.yaml
# with the age identity derived from it — so afterwards, re-key arca.yaml to the
# new host:
#   ssh root@<ip> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | nix run nixpkgs#ssh-to-age
#   # put that age recipient on the &arca key in .sops.yaml, then:
#   sops updatekeys secrets/arca.yaml   # and `cachectl deploy`
def "main install" [
  ip: string # the fresh box's public IP
] {
  cd (dots-dir)
  nix run github:nix-community/nixos-anywhere -- --flake ".#arca" --target-host $"root@($ip)"
}

# Push a config update to the installed box (nixos-rebuild switch over the
# tailnet), then reboot and GC. The reboot comes before GC because the booted
# generation can't be reclaimed until it's no longer booted; we wait for the box
# to return (its boot id changes) before removing old generations.
def "main deploy" [] {
  deploy-box
  let target = (arca-ssh)
  print "→ rebooting arca into the new generation..."
  let before = (
    ^ssh $target cat /proc/sys/kernel/random/boot_id
    | complete
    | get stdout
    | str trim
  )
  if ($before | is-empty) {
    error make {msg: "couldn't read arca's boot id before reboot"}
  }
  # The connection drops as the box goes down, so ignore the result.
  ^ssh $target systemctl reboot | complete | ignore
  print "→ waiting for arca to come back..."
  mut back = false
  for _ in 1..60 {
    sleep 5sec
    let r = (
      ^ssh -o ConnectTimeout=5 -o BatchMode=yes $target cat /proc/sys/kernel/random/boot_id
      | complete
    )
    if ($r.exit_code == 0) and (($r.stdout | str trim) != $before) {
      $back = true
      break
    }
  }
  if not $back {
    error make {msg: "arca did not come back within ~5 min of the reboot"}
  }
  print "→ collecting old generations..."
  ^ssh $target nix-collect-garbage --delete-old
  print "✓ deployed, rebooted, and GC'd."
}

# Reconcile every declared repo's ATTIC_TOKEN: mint a fresh push/pull token for
# each cache in modules/_lib/caches.nix and install it as that repo's secret.
# Idempotent — run after adding a project or to rotate every token. Deploys first
# if a declared cache isn't on the box yet.
def "main sync" [] {
  let caches = (declared-caches)
  let domain = (cache-domain)
  let missing = $caches | where {|c| not (cache-exists $c.name $domain) } | get name
  if ($missing | is-not-empty) {
    print $"Not on the box yet: ($missing | str join ', ') — deploying to create them first."
    deploy-box
  }
  for c in $caches {
    mint-token $c.name | gh secret set ATTIC_TOKEN --repo $c.repo
    print $"✓ ($c.repo) ← ATTIC_TOKEN for ($c.name)"
  }
}

# Desired-vs-actual for every declared cache: whether it's on the box (probed
# over HTTP) and whether its repo has an ATTIC_TOKEN secret. Tokens are stateless
# JWTs with no server-side registry, so this is the view of which repos are wired.
def "main list" [] {
  let domain = (cache-domain)
  declared-caches | each {|c|
    let token_set = (
      gh secret list --repo $c.repo --json name
      | from json | any {|s| $s.name == "ATTIC_TOKEN" }
    )
    { cache: $c.name, repo: $c.repo, on_box: (cache-exists $c.name $domain), token_set: $token_set }
  }
}
