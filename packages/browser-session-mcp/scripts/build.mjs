#!/usr/bin/env node
import { build } from "esbuild";

const banner = {
  // Keep Node running as-is (shebang for CLI use); then re-introduce
  // `require` for the few bundled deps that still call it under ESM.
  js: [
    "#!/usr/bin/env node",
    `import { createRequire } from "node:module";`,
    `const require = createRequire(import.meta.url);`,
  ].join("\n"),
};

const common = {
  bundle: true,
  platform: "node",
  format: "esm",
  target: "node22",
  packages: "bundle",
  banner,
};

await Promise.all([
  build({
    ...common,
    entryPoints: ["src/index.ts"],
    outfile: "dist/index.js",
  }),
  build({
    ...common,
    entryPoints: ["src/reaper.ts"],
    outfile: "dist/reaper.js",
  }),
  build({
    ...common,
    entryPoints: ["src/listener.ts"],
    outfile: "dist/listener.js",
  }),
]);
