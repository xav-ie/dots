# Lists the files osgrep has indexed in a repo, read straight from its meta
# cache (the LMDB keys ARE the indexed file paths). osgrep has no built-in
# "list indexed files" command — `osgrep list` only prints index sizes.
#
# Usage:
#   osgrep-indexed [repo]   list files indexed in a repo (default: cwd)
#   osgrep-indexed --all    list files across every repo in the indexing
#                           allowlist (the sops config the timer uses), as
#                           absolute paths (greppable across repos)
#   -s/--size               prefix each file with its chunk size
#
# Audit example: osgrep-indexed --all | grep -E '\.min\.|node_modules|\.devenv'
{
  writeShellApplication,
  writeText,
  nodejs,
}:
let
  # osgrep is installed via npm (not nix), so reuse the lmdb it ships with
  # rather than packaging the native module ourselves.
  reader = writeText "osgrep-indexed.cjs" ''
    "use strict";
    const os = require("node:os");
    const path = require("node:path");
    const fs = require("node:fs");

    const lmdbDir = path.join(
      os.homedir(),
      ".npm/lib/node_modules/osgrep/node_modules/lmdb",
    );
    let open;
    try {
      open = require(lmdbDir).open;
    } catch {
      console.error("osgrep-indexed: could not load lmdb from " + lmdbDir);
      console.error("  is osgrep installed? (npm global; it provides the reader)");
      process.exit(1);
    }

    const args = process.argv.slice(2);
    const showSize = args.includes("--size") || args.includes("-s");
    const all = args.includes("--all") || args.includes("-a");
    const pos = args.find((a) => !a.startsWith("-"));

    function metaPath(repo) {
      return path.join(repo, ".osgrep", "cache", "meta.lmdb");
    }

    // The indexing allowlist is the same sops blob the timer reads — no need to
    // scan the filesystem when we already know which repos we index. Repos with
    // no index yet are skipped.
    function allowlist() {
      const configPath =
        process.env.OSGREP_INDEX_CONFIG || "/run/secrets/mgrep/config";
      let folders;
      try {
        folders = JSON.parse(fs.readFileSync(configPath, "utf8")).folders || [];
      } catch {
        console.error("osgrep-indexed: could not read config " + configPath);
        process.exit(1);
      }
      return folders.filter((repo) => fs.existsSync(metaPath(repo))).sort();
    }

    function readRepo(repo) {
      const db = open({ path: metaPath(repo), compression: true, readOnly: true });
      const rows = [];
      for (const entry of db.getRange()) {
        const size = entry.value && entry.value.size ? entry.value.size : 0;
        rows.push({ f: String(entry.key), kb: Math.round(size / 1024) });
      }
      db.close();
      rows.sort((a, b) => (a.f < b.f ? -1 : a.f > b.f ? 1 : 0));
      return rows;
    }

    function printRow(file, kb) {
      process.stdout.write(
        showSize ? String(kb).padStart(7) + "K  " + file + "\n" : file + "\n",
      );
    }

    if (all) {
      const repos = allowlist();
      let totalFiles = 0;
      for (const repo of repos) {
        const rows = readRepo(repo);
        totalFiles += rows.length;
        for (const r of rows) printRow(path.join(repo, r.f), r.kb);
      }
      process.stderr.write(
        repos.length + " repos, " + totalFiles + " files indexed\n",
      );
    } else {
      const repo = path.resolve(pos || process.cwd());
      if (!fs.existsSync(metaPath(repo))) {
        console.error("osgrep-indexed: no index at " + metaPath(repo));
        console.error("  run 'osgrep index' in that repo first");
        process.exit(1);
      }
      const rows = readRepo(repo);
      for (const r of rows) printRow(r.f, r.kb);
      process.stderr.write(rows.length + " files indexed in " + repo + "\n");
    }
  '';
in
writeShellApplication {
  name = "osgrep-indexed";
  runtimeInputs = [ nodejs ];
  text = ''
    exec node ${reader} "$@"
  '';
}
