// Ambient declarations for the ags bundler's virtual/asset imports, so tsgo can
// typecheck the app. Mirrors the ags project scaffold (cli/data/env.d.ts).
declare const SRC: string;

declare module "inline:*" {
  const content: string;
  export default content;
}

declare module "*.scss" {
  const content: string;
  export default content;
}

declare module "*.css" {
  const content: string;
  export default content;
}

declare module "*.blp" {
  const content: string;
  export default content;
}

// ags's lib/overrides.ts lazily references these astal *service* modules. The
// calendar app uses none of them, so declare them loosely (→ `any`) instead of
// generating their (heavy) @girs types just to satisfy ags's import graph.
declare module "gi://AstalApps";
declare module "gi://AstalBattery";
declare module "gi://AstalBluetooth";
declare module "gi://AstalHyprland";
declare module "gi://AstalMpris";
declare module "gi://AstalNetwork";
declare module "gi://AstalNotifd";
declare module "gi://AstalPowerProfiles";
declare module "gi://AstalWp";
declare module "gi://AstalTray";
