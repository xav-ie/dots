// Ambient declarations for the Firefox chrome/autoconfig globals used by the
// impure shell (main.ts). The geometry core uses none of these. Typed loosely
// as `any` on purpose — this is XPCOM glue, not the unit-tested surface.
//
// No import/export here: a declaration file with neither is treated as a global
// script, so these become ambient globals visible to the (module) main.ts.

declare const Components: {
  interfaces: any;
  classes: any;
  utils: { reportError(msg: unknown): void };
};
declare const Services: any;
declare const ChromeUtils: any;
