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
writers.writePython3Bin "firefox-router" { flakeIgnore = [ "E501" ]; } ''
  import glob
  import json
  import os
  import shutil
  import sqlite3
  import subprocess
  import sys
  from configparser import ConfigParser
  from fnmatch import fnmatch
  from urllib.parse import urlsplit

  RULES_PATH = os.environ.get("FIREFOX_ROUTER_RULES") or "/run/secrets/firefox-router/rules"


  def load_rules():
      try:
          with open(RULES_PATH) as f:
              return json.load(f)
      except Exception:
          return None


  RULES = load_rules()


  def ff_root():
      home = os.path.expanduser("~")
      if sys.platform == "darwin":
          return os.path.join(home, "Library", "Application Support", "Firefox")
      return os.path.join(home, ".mozilla", "firefox")


  def store_id(root):
      ini = os.path.join(root, "profiles.ini")
      cp = ConfigParser()
      try:
          cp.read(ini)
      except Exception:
          return None
      fallback = None
      for sec in cp.sections():
          if not sec.startswith("Profile"):
              continue
          sid = cp[sec].get("storeid")
          if not sid:
              continue
          fallback = sid
          if cp[sec].get("default") == "1":
              return sid
      return fallback


  def group_db(root):
      groups = os.path.join(root, "Profile Groups")
      sid = store_id(root)
      if sid:
          cand = os.path.join(groups, sid + ".sqlite")
          if os.path.exists(cand):
              return cand
      dbs = glob.glob(os.path.join(groups, "*.sqlite"))
      if not dbs:
          return None
      return max(dbs, key=os.path.getmtime)


  def profile_dir(root, name):
      db = group_db(root)
      if not db:
          return None
      try:
          con = sqlite3.connect("file:%s?mode=ro&immutable=1" % db, uri=True)
          row = con.execute(
              "SELECT path FROM Profiles WHERE name = ?", (name,)
          ).fetchone()
          con.close()
      except Exception:
          return None
      if not row or not row[0]:
          return None
      path = row[0]
      if not os.path.isabs(path):
          path = os.path.join(root, path)
      return path


  def pick_profile(url):
      if not RULES:
          return None
      parts = urlsplit(url)
      host = parts.hostname or ""
      path = parts.path or "/"
      hostpath = host + path
      for rule in RULES.get("rules", []):
          for pat in rule.get("match", []):
              target = hostpath if "/" in pat else host
              if fnmatch(target, pat):
                  return rule["profile"]
      return RULES.get("default")


  def firefox_bin():
      env = os.environ.get("FIREFOX_BIN")
      if env:
          return env
      if sys.platform == "darwin":
          return "/Applications/Firefox.app/Contents/MacOS/firefox"
      return shutil.which("firefox") or "firefox"


  def main():
      urls = [a for a in sys.argv[1:] if "://" in a]
      ff = firefox_bin()
      root = ff_root()
      if not urls:
          # No URL: just open Firefox (default profile).
          launch(ff, [])
          return
      for url in urls:
          args = []
          name = pick_profile(url)
          if name:
              pdir = profile_dir(root, name)
              if pdir:
                  args = ["--profile", pdir, "--profiles-activate"]
          launch(ff, args + [url])


  def launch(ff, args):
      devnull = open(os.devnull, "wb")
      subprocess.Popen(
          [ff] + args,
          stdout=devnull,
          stderr=devnull,
          start_new_session=True,
      )


  if __name__ == "__main__":
      main()
''
