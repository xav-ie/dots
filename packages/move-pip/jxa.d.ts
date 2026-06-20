// Minimal ambient declarations for the JXA (osascript) runtime globals used by
// move-pip.js — no @jxa/types dependency. The ObjC bridge ($) and the System
// Events automation surface (Application) are dynamically typed in JXA, so they
// are intentionally `any`; the geometry values that actually warrant checking
// are annotated inline in move-pip.js (the Rect typedef and number[] casts).

declare function Application(name: string): any;
declare const ObjC: { import(framework: string): void };
declare const $: any;
