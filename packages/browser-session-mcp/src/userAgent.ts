import type { Browser } from "puppeteer-core";
import type { Protocol } from "devtools-protocol";

export type UAOverride = {
  userAgent: string;
  userAgentMetadata: Protocol.Emulation.UserAgentMetadata;
};

// Tracking chrome-headless-shell's own version means the spoof advances when
// the binary is upgraded — no constant to bump by hand.
let cachedVersion: { full: string; major: string } | undefined;

async function chromeVersion(
  browser: Browser,
): Promise<{ full: string; major: string }> {
  if (cachedVersion) return cachedVersion;
  // browser.version() returns e.g. "HeadlessChrome/146.0.7680.31"
  const raw = await browser.version();
  const m = /\/(\d+(?:\.\d+){2,3})/.exec(raw);
  const full = m?.[1] ?? "146.0.7680.31";
  cachedVersion = { full, major: full.split(".")[0]! };
  return cachedVersion;
}

export async function resolveUA(
  browser: Browser,
  opts: { useMobileUA?: boolean },
): Promise<UAOverride> {
  const { full, major } = await chromeVersion(browser);

  // No "HeadlessChrome" entry — that's the point of the spoof. Brand list
  // mirrors what stock Chrome sends for Sec-CH-UA.
  const brands = [
    { brand: "Chromium", version: major },
    { brand: "Google Chrome", version: major },
    { brand: "Not.A/Brand", version: "8" },
  ];
  const fullVersionList = [
    { brand: "Chromium", version: full },
    { brand: "Google Chrome", version: full },
    { brand: "Not.A/Brand", version: "8.0.0.0" },
  ];

  if (opts.useMobileUA) {
    return {
      userAgent: `Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${full} Mobile Safari/537.36`,
      userAgentMetadata: {
        brands,
        fullVersionList,
        platform: "Android",
        platformVersion: "14",
        architecture: "",
        model: "Pixel 8",
        mobile: true,
        formFactors: ["Mobile"],
      },
    };
  }

  return {
    userAgent: `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${full} Safari/537.36`,
    userAgentMetadata: {
      brands,
      fullVersionList,
      platform: "Linux",
      platformVersion: "",
      architecture: "x86",
      model: "",
      mobile: false,
      formFactors: ["Desktop"],
    },
  };
}
