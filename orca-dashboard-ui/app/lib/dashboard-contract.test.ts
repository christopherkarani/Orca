import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

import {
  DashboardModeContext,
  FeedHealthNotice,
  MachineContextFields,
  WorkspaceOnlyGate,
} from "./dashboard-mode.ts";
import { visibleNavigation } from "./nav.ts";
import { sessionKey } from "./types.ts";

function renderInMode(mode: "machine" | "workspace", child: React.ReactNode): string {
  return renderToStaticMarkup(
    React.createElement(
      DashboardModeContext.Provider,
      { value: { mode, loading: false } },
      child,
    ),
  );
}

test("session identity includes its workspace", () => {
  assert.notEqual(
    sessionKey({ id: "same", workspace_root: "/a" }),
    sessionKey({ id: "same", workspace_root: "/b" }),
  );
});

test("machine navigation renders only global-safe destinations", () => {
  const machineLabels = visibleNavigation("machine").map((tab) => tab.label);
  const workspaceLabels = visibleNavigation("workspace").map((tab) => tab.label);
  assert.deepEqual(machineLabels, ["Overview", "Activity", "Integrations"]);
  assert.ok(workspaceLabels.includes("Policy"));
  assert.ok(workspaceLabels.includes("Secretless"));
});

test("workspace-only routes do not mount their controls in machine mode", () => {
  const controls = React.createElement("button", { "data-testid": "policy-save" }, "Save policy");
  const machine = renderInMode("machine", React.createElement(WorkspaceOnlyGate, null, controls));
  const workspace = renderInMode("workspace", React.createElement(WorkspaceOnlyGate, null, controls));

  assert.doesNotMatch(machine, /data-testid="policy-save"/);
  assert.match(machine, /Select a workspace/);
  assert.match(machine, /orca dashboard --workspace/);
  assert.match(workspace, /data-testid="policy-save"/);
});

test("machine activity renders workspace, host, and degraded-feed context", () => {
  const context = renderToStaticMarkup(
    React.createElement(MachineContextFields, { workspaceRoot: "/work/a", host: "build-01" }),
  );
  const warning = renderToStaticMarkup(
    React.createElement(FeedHealthNotice, {
      status: { feed_health: { status: "degraded", skipped_lines: 3 } },
    }),
  );

  assert.match(context, /Workspace/);
  assert.match(context, /\/work\/a/);
  assert.match(context, /Host/);
  assert.match(context, /build-01/);
  assert.match(warning, /skipped 3 malformed lines/);
});
