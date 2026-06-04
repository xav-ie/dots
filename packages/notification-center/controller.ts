import { createState } from "ags";

// The center window binds its visibility to `centerOpen`. The resident app's
// requestHandler (app.ts) flips this when `notifctl -t` re-invokes the binary;
// Escape and click-away close it from inside NotificationCenter.tsx.
export const [centerOpen, setCenterOpen] = createState(false);

export function toggleCenter(): void {
  setCenterOpen((v) => !v);
}

export function setCenter(open: boolean): void {
  setCenterOpen(open);
}
