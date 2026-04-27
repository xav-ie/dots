import type { Page } from "puppeteer-core";

/**
 * Format a page's accessibility tree as indented text. Cheap, human-readable,
 * and enough for agents to "see" the page without a screenshot round-trip.
 *
 * We intentionally omit uid-based interaction — callers use CSS selectors for
 * click/type. Keeps the surface small for v1.
 */
export async function accessibilitySnapshot(page: Page): Promise<string> {
  const tree = await page.accessibility.snapshot({ interestingOnly: true });
  if (!tree) return "(empty accessibility tree)";
  const lines: string[] = [];
  walk(tree, 0, lines);
  return lines.join("\n");
}

type AXNode = Awaited<ReturnType<Page["accessibility"]["snapshot"]>>;

function walk(node: NonNullable<AXNode>, depth: number, out: string[]): void {
  const prefix = "  ".repeat(depth);
  const role = node.role ?? "unknown";
  const name = node.name ? ` "${escape(node.name)}"` : "";
  const value =
    node.value != null ? ` [value=${JSON.stringify(node.value)}]` : "";
  const level =
    node.level != null && typeof node.level === "number"
      ? ` level=${node.level}`
      : "";
  out.push(`${prefix}${role}${name}${value}${level}`);
  for (const child of node.children ?? []) {
    walk(child, depth + 1, out);
  }
}

function escape(s: string): string {
  return s.length > 120 ? s.slice(0, 117) + "..." : s;
}
