import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { feedHealthMessage, sessionKey } from "./types.ts";
import { visibleNavigation } from "./nav.ts";

test("session identity includes its workspace", () => {
  assert.notEqual(
    sessionKey({ id: "same", workspace_root: "/a" }),
    sessionKey({ id: "same", workspace_root: "/b" }),
  );
});

test("machine navigation excludes workspace-only pages", () => {
  assert.ok(!visibleNavigation("machine").some((tab) => tab.label === "Policy"));
  assert.ok(!visibleNavigation("machine").some((tab) => tab.label === "Secretless"));
});

test("overview and activity expose machine-wide context and feed health", () => {
  const overview = readFileSync(new URL("../page.tsx", import.meta.url), "utf8");
  const activity = readFileSync(new URL("../activity/page.tsx", import.meta.url), "utf8");

  assert.match(overview, /Workspaces/);
  assert.match(activity, /Workspace/);
  assert.match(activity, /Host/);
  assert.match(activity, /feedWarning/);
  assert.match(
    feedHealthMessage({ feed_health: "degraded", feed_skipped_lines: 2 }) ?? "",
    /skipped 2 malformed lines/,
  );
  assert.match(
    feedHealthMessage({ feed_health: { status: "degraded", skipped_lines: 3 } }) ?? "",
    /skipped 3 malformed lines/,
  );
});
