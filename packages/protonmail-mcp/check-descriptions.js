#!/usr/bin/env node
// Fail the build if a tool's reworded MCP description regresses.
//
// Spawns the just-built server over real stdio MCP, lists its tools, and
// compares against expected-descriptions.json — the set this package's
// tool-descriptions.patch targets. Listing tools never requires a live
// Proton Bridge: SMTP/IMAP connect failures are logged and swallowed, not
// fatal. A server bump that renames/rewords a tool makes the patch fail to
// apply first; this catches the case where it still applies but no longer
// lands on the right text.

"use strict";

const { spawn } = require("node:child_process");
const fs = require("node:fs");

const [, , bundlePath, expectedPath] = process.argv;
if (!bundlePath || !expectedPath) {
  console.error("usage: check-descriptions.js <bundle.js> <expected.json>");
  process.exit(2);
}

const expected = JSON.parse(fs.readFileSync(expectedPath, "utf8"));

const child = spawn(process.execPath, [bundlePath], {
  env: {
    ...process.env,
    PROTONMAIL_USERNAME: "check-dummy@example.com",
    PROTONMAIL_PASSWORD: "check-dummy",
    // Loopback with nothing listening — connect fails fast and is
    // swallowed by the server instead of hanging.
    PROTONMAIL_SMTP_HOST: "127.0.0.1",
    PROTONMAIL_SMTP_PORT: "1025",
    PROTONMAIL_IMAP_HOST: "127.0.0.1",
    PROTONMAIL_IMAP_PORT: "1143",
  },
  stdio: ["pipe", "pipe", "pipe"],
});

let stdout = "";
let stderr = "";
child.stdout.on("data", (chunk) => {
  stdout += chunk;
});
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

const send = (msg) => {
  child.stdin.write(JSON.stringify(msg) + "\n");
};

const timeout = setTimeout(() => {
  console.error("Timed out waiting for tools/list.");
  console.error("stderr so far:\n" + stderr);
  child.kill();
  process.exit(1);
}, 15000);

send({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "check-descriptions", version: "0.0.0" },
  },
});

let step = 0;
const tryParseLines = () => {
  const lines = stdout.split("\n").filter(Boolean);
  if (step === 0 && lines.length >= 1) {
    step = 1;
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    send({ jsonrpc: "2.0", id: 2, method: "tools/list" });
  }
  if (step === 1 && lines.length >= 2) {
    clearTimeout(timeout);
    const response = JSON.parse(lines[1]);
    const tools = response.result.tools;
    const actual = Object.fromEntries(
      tools.map((t) => [t.name, t.description || ""]),
    );

    const failures = [];
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

    child.kill();
    if (failures.length > 0) {
      console.error("Tool description check failed:");
      for (const f of failures) console.error("  - " + f);
      process.exit(1);
    }
    console.log(
      `OK: ${Object.keys(expected).length} tool descriptions match expected-descriptions.json`,
    );
    process.exit(0);
  }
};

child.stdout.on("data", tryParseLines);

child.on("exit", (code) => {
  if (step < 1) {
    clearTimeout(timeout);
    console.error(`Server exited early with code ${code}.`);
    console.error("stderr:\n" + stderr);
    process.exit(1);
  }
});
