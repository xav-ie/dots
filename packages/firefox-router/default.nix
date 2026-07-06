{ writers }:
# Cross-platform URL -> Firefox-profile router. The OS default link handler
# (Linux .desktop / macOS FirefoxRouter.app) hands us a URL; we resolve the
# target profile's absolute directory from Firefox's SQLite-backed profile
# group and exec the Firefox binary directly with --profile.
#
# Launch by absolute path (not `-P name`): on the new profile system the
# friendly names ("Work"/"Personal") live only in the Profile Groups DB, and
# Personal isn't in profiles.ini at all.
#
# Rules are NOT baked in (they name private clients): they're read at runtime
# from a sops-decrypted JSON file ($FIREFOX_ROUTER_RULES or
# /run/secrets/firefox-router/rules). Schema — see rules.example.json:
#   {"default": "Personal",
#    "rules": [{"profile": "Work", "match": ["github.com/outsmartly/*", ...]}]}
# If the file is missing/unreadable we launch Firefox with NO --profile and let
# it pick (its normal behaviour) — the binary never invents a routing policy.
writers.writePython3Bin "firefox-router" { flakeIgnore = [ "E501" ]; } (
  builtins.readFile ./router.py
)
