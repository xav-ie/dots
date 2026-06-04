// Weekly reconcile for the mgrep store. Works around mgrep's broken prune
// (its delete uses the file path, but the API requires the file's UUID id, so
// `mgrep search --sync` never actually removes anything). This enumerates the
// store and deletes — by id — every file that is now ignored by its repo's
// .mgrepignore, no longer on disk, or not under any allowlisted repo.
//
// Auth reuses mgrep's own token exchange (or MXBAI_API_KEY from the service's
// EnvironmentFile), refreshed periodically since the JWT is short-lived.
const HOME = process.env.HOME;
const pkg = (rel) => HOME + "/.npm/lib/node_modules/@mixedbread/mgrep/" + rel;

const { default: Mixedbread } = await import(
  pkg("node_modules/@mixedbread/sdk/index.js")
);
const { getJWTToken } = await import(pkg("dist/lib/auth.js"));
const { default: ignore } = await import(pkg("node_modules/ignore/index.js"));
const fs = await import("node:fs");
const path = await import("node:path");

const mk = async () =>
  new Mixedbread({
    baseURL: "https://api.mixedbread.com",
    apiKey: await getJWTToken(),
  });
let client = await mk();
const refresher = setInterval(
  async () => {
    try {
      client = await mk();
    } catch {}
  },
  4 * 60 * 1000,
);
refresher.unref?.();

// Allowlisted repo roots = dirs that have a generated .mgrepignore. Each repo's
// own .mgrepignore is the source of truth, so this stays in sync automatically.
const roots = [];
for (const base of [HOME + "/Work", HOME + "/Projects"]) {
  let entries;
  try {
    entries = fs.readdirSync(base, { withFileTypes: true });
  } catch {
    continue;
  }
  for (const n of entries) {
    const ignoreFile = path.join(base, n.name, ".mgrepignore");
    if (n.isDirectory() && fs.existsSync(ignoreFile))
      roots.push(path.join(base, n.name));
  }
}
// Safety: an empty allowlist would mark every stored file an orphan and delete
// the whole index. The allowlist comes from .mgrepignore files written by
// mgrep-sync from the sops config, so "no roots" means that hasn't run yet (or
// the secret is missing) — bail rather than wipe.
if (roots.length === 0) {
  console.log(
    "reconcile: no allowlisted roots (.mgrepignore) found — aborting",
  );
  process.exit(0);
}
const filters = new Map();
for (const r of roots) {
  try {
    filters.set(
      r,
      ignore().add(fs.readFileSync(path.join(r, ".mgrepignore"), "utf8")),
    );
  } catch {
    filters.set(r, ignore());
  }
}
const rootOf = (p) => roots.find((r) => p.startsWith(r + "/"));

const del = [];
let page = await client.stores.files.list("mgrep", { limit: 100 });
while (true) {
  for (const f of page.data) {
    const p = f.metadata?.path || f.external_id || "";
    const r = rootOf(p);
    if (!r) {
      del.push(f.id);
      continue;
    } // orphan: not under any allowlisted repo
    const rel = p.slice(r.length + 1);
    let gone = false;
    try {
      fs.accessSync(p);
    } catch {
      gone = true;
    }
    if (gone || (rel && filters.get(r).ignores(rel))) del.push(f.id);
  }
  const after = page.pagination?.has_more ? page.pagination?.last_cursor : null;
  if (!after) break;
  page = await client.stores.files.list("mgrep", { limit: 100, after });
}
console.log(
  "reconcile: " + del.length + " stale/ignored/orphan files to delete",
);

let done = 0,
  err = 0,
  idx = 0;
async function worker() {
  while (idx < del.length) {
    const id = del[idx++];
    try {
      await client.stores.files.delete(id, { store_identifier: "mgrep" });
    } catch {
      try {
        await (
          await mk()
        ).stores.files.delete(id, { store_identifier: "mgrep" });
      } catch {
        err++;
      }
    }
    if (++done % 200 === 0)
      console.log("  " + done + "/" + del.length + " (err " + err + ")");
  }
}
await Promise.all(Array.from({ length: 12 }, worker));
clearInterval(refresher);
console.log("reconcile done: deleted " + (done - err) + ", errors " + err);
