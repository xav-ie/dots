// Bridges the resident instance's requestHandler (app.ts) to the live Spotlight
// component. app.ts calls requestMode(id) whenever a keybind re-launches the
// binary with a mode argument; Spotlight registers the actual switch/toggle
// logic via onRequest().
let handler: ((id: string) => void) | null = null;

export function onRequest(fn: (id: string) => void): void {
  handler = fn;
}

export function requestMode(id: string): void {
  handler?.(id);
}
