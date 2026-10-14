// Minimal ambient declarations so `tsc --strict` passes with zero npm
// dependencies. Covers only what this package uses: the Bun runtime surface
// and the handful of node builtins Bun implements (which is all of them, but
// declaring just these keeps the honest contract visible).
//
// When editing, keep in lockstep with actual usage in src/*.ts.

interface ImportMeta {
  readonly path: string;
  readonly main: boolean;
  readonly url: string;
}

declare const process: {
  readonly env: Record<string, string | undefined>;
  readonly execPath: string;
};

declare const Bun: {
  /** Full argv: [bun, script, ...args] interpreted; [binary, ...args] compiled. */
  readonly argv: string[];
  readonly stdin: ReadableStream<Uint8Array>;
  file(path: string): {
    json<T = unknown>(): Promise<T>;
    text(): Promise<string>;
  };
  write(path: string, data: string | Uint8Array): Promise<number>;
};

declare module "node:child_process" {
  // Classic three-arg form only — bun's spawn rejects the node array-form
  // shorthand (spawn(["cmd", ...args], opts)) with ERR_INVALID_ARG_TYPE.
  export function spawn(
    command: string,
    args: readonly string[],
    options: {
      detached?: boolean;
      stdio?: string | readonly string[];
      env?: Record<string, string>;
    },
  ): {
    stdin: { end(data?: string): void } | null;
    stdout: {
      on(event: "data", listener: (chunk: unknown) => void): void;
    } | null;
    on(event: "error" | "close", listener: () => void): void;
    kill(): void;
    unref(): void;
  };
}

declare module "node:fs" {
  export function existsSync(path: string): boolean;
  export function readFileSync(path: string, encoding: "utf8"): string;
  export function writeFileSync(path: string, data: string): void;
  export function appendFileSync(path: string, data: string): void;
  export function mkdirSync(
    path: string,
    options: { recursive: boolean },
  ): void;
  export function statSync(path: string): { mtimeMs: number };
  export function renameSync(oldPath: string, newPath: string): void;
  export function unlinkSync(path: string): void;
}

declare module "node:crypto" {
  export function createHash(algorithm: "sha256"): {
    update(data: string): this;
    digest(encoding: "hex"): string;
  };
  export function randomUUID(): string;
}

declare module "node:os" {
  export function homedir(): string;
}

declare module "node:path" {
  export function join(...paths: string[]): string;
  export function dirname(path: string): string;
}
