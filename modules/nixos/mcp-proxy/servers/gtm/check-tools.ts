// Fail the build if a tool's reworded MCP description regresses.
//
// stdio.ts can't list tools offline: its main() calls oauth.getAccessToken()
// — a real network call needing a real refresh token — before it even
// registers a tool. So this imports the tool registration functions
// directly and feeds them a stub server that just records what each one
// calls .tool(name, description, ...) with, which needs neither network nor
// credentials. Compares the result against expected-descriptions.json — the
// set this package's tool-descriptions.patch targets. A server bump that
// renames/rewords a tool makes the patch fail to apply first; this catches
// the case where it still applies but no longer lands on the right text.
import * as fs from "node:fs";
import { tools } from "./tools";
import { removeMCPServerData } from "./tools/removeMCPServerData";

const expectedPath = process.argv[2];
if (!expectedPath) {
  console.error("usage: check-tools.cjs <expected.json>");
  process.exit(2);
}

const expected: Record<string, string> = JSON.parse(
  fs.readFileSync(expectedPath, "utf8"),
);

const actual: Record<string, string> = {};
const fakeServer = {
  tool: (name: string, description: string, ..._rest: unknown[]) => {
    actual[name] = description;
  },
} as never;

for (const register of tools) {
  if (register === removeMCPServerData) continue;
  (register as (server: unknown, ctx: unknown) => void)(fakeServer, {
    props: { accessToken: "stub" },
    env: {},
  });
}

const failures: string[] = [];
for (const [name, want] of Object.entries(expected)) {
  const got = actual[name];
  if (got === undefined) {
    failures.push(
      `${name}: tool no longer registered (upstream renamed/removed it?)`,
    );
  } else if (got !== want) {
    failures.push(
      `${name}: description mismatch\n  want: ${JSON.stringify(want)}\n  got:  ${JSON.stringify(got)}`,
    );
  }
}

if (failures.length > 0) {
  console.error("Tool description check failed:");
  for (const f of failures) console.error("  - " + f);
  process.exit(1);
}
console.log(
  `OK: ${Object.keys(expected).length} tool descriptions match expected-descriptions.json`,
);
