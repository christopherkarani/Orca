const token = document.querySelector('meta[name="orca-dashboard-token"]').content;
const state = {
  status: null,
  policy: null,
};

const els = {
  summaryGrid: document.querySelector("#summaryGrid"),
  quickActions: document.querySelector("#quickActions"),
  blockedPreview: document.querySelector("#blockedPreview"),
  sessionList: document.querySelector("#sessionList"),
  blockedTimeline: document.querySelector("#blockedTimeline"),
  policyText: document.querySelector("#policyText"),
  policyHelp: document.querySelector("#policyHelp"),
  presetList: document.querySelector("#presetList"),
  integrationGrid: document.querySelector("#integrationGrid"),
  commandOutput: document.querySelector("#commandOutput"),
  toastRegion: document.querySelector("#toastRegion"),
};

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => showView(button.dataset.view));
});

document.querySelector("#refreshButton").addEventListener("click", refresh);
document.querySelector("#savePolicyButton").addEventListener("click", savePolicy);
document.querySelector("#clearOutputButton").addEventListener("click", () => {
  els.commandOutput.textContent = "No command has run yet.";
});

document.body.addEventListener("click", (event) => {
  const actionButton = event.target.closest("[data-action]");
  if (actionButton) {
    runAction(actionButton.dataset.action);
    return;
  }
  const presetButton = event.target.closest("[data-preset]");
  if (presetButton) {
    initPreset(presetButton.dataset.preset);
  }
});

refresh();

function showView(name) {
  document.querySelectorAll(".nav-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === name);
  });
  document.querySelectorAll("[data-view-panel]").forEach((panel) => {
    panel.classList.toggle("active", panel.dataset.viewPanel === name);
  });
}

async function refresh() {
  try {
    const [status, policy] = await Promise.all([
      getJson("/api/status"),
      getJson("/api/policy"),
    ]);
    state.status = status;
    state.policy = policy;
    renderStatus(status);
    renderPolicy(policy);
  } catch (error) {
    toast(`Refresh failed: ${error.message}`);
  }
}

async function getJson(path) {
  const response = await fetch(path, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`${path} returned ${response.status}`);
  return response.json();
}

async function postJson(path, body) {
  const response = await fetch(path, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-Orca-Dashboard-Token": token,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${path} returned ${response.status}`);
  return response.json();
}

function renderStatus(data) {
  const policy = data.policy;
  const license = data.license;
  const ci = data.ci_readiness;
  const blockedCount = data.blocked_actions.length;
  const sessionCount = data.sessions.length;
  els.summaryGrid.innerHTML = [
    metric("CLI", "Installed", `Orca ${data.orca.version}`),
    metric("Policy", policy.exists ? (policy.valid ? "Valid" : "Invalid") : "Missing", policy.exists ? policy.path : "Create one from a preset"),
    metric("License", license.tier, license.report_export ? "report export enabled" : "core safety enabled"),
    metric("CI", ci.ok ? "Ready" : "Needs work", ci.error || ci.checks.map((check) => `${check.name}: ${check.status}`).join(", ")),
    metric("Prevented", `${blockedCount}`, blockedCount === 1 ? "blocked action found" : "blocked actions found"),
    metric("Sessions", `${sessionCount}`, data.orca.workspace_root),
  ].join("");

  els.quickActions.innerHTML = data.quick_actions.map((action) => `
    <div class="action-card">
      <code class="command-line">${escapeHtml(action.command)}</code>
      <button class="button secondary" type="button" data-action="${escapeHtml(action.id)}">Run</button>
    </div>
  `).join("");

  renderBlockedList(els.blockedPreview, data.blocked_actions, true);
  renderBlockedList(els.blockedTimeline, data.blocked_actions, false);
  renderSessions(data.sessions);
  renderIntegrations(data.plugins);
}

function metric(label, value, detail) {
  return `
    <article class="metric">
      <span class="caption">${escapeHtml(label)}</span>
      <div class="value">${escapeHtml(value)}</div>
      <div class="detail">${escapeHtml(detail)}</div>
    </article>
  `;
}

function renderBlockedList(container, actions, compact) {
  if (!actions.length) {
    container.innerHTML = `<div class="timeline-item"><h5>No denied actions found</h5><p class="caption">Run Orca with an agent, then replay denied events here.</p></div>`;
    return;
  }
  const visible = compact ? actions.slice(0, 4) : actions;
  container.innerHTML = visible.map((action) => `
    <article class="timeline-item">
      <header>
        <h5>${escapeHtml(action.event_type)}</h5>
        <span class="status-pill ${action.verified ? "ok" : "warn"}">${action.verified ? "verified" : "unverified"}</span>
      </header>
      <div class="meta-grid">
        ${meta("Target", action.target)}
        ${meta("Decision", action.decision || "deny")}
        ${meta("Rule", action.rule || "not recorded")}
        ${meta("Reason", action.reason || "not recorded")}
      </div>
    </article>
  `).join("");
}

function renderSessions(sessions) {
  if (!sessions.length) {
    els.sessionList.innerHTML = `<div class="session-card"><h5>No sessions yet</h5><p class="caption">Session artifacts appear after running an agent through Orca.</p></div>`;
    return;
  }
  els.sessionList.innerHTML = sessions.map((session) => `
    <article class="session-card">
      <header>
        <h5>${escapeHtml(session.id)}</h5>
        <span class="status-pill ${session.verified ? "ok" : "warn"}">${session.verified ? "verified" : "unverified"}</span>
      </header>
      <div class="meta-grid">
        ${meta("Command", session.command || "unknown")}
        ${meta("Policy", session.policy || "unknown")}
        ${meta("Status", session.status || "unknown")}
        ${meta("Denied", String(session.denied_count))}
      </div>
    </article>
  `).join("");
}

function renderPolicy(policy) {
  els.policyText.value = policy.text || "";
  const summary = policy.summary;
  els.policyHelp.textContent = summary.exists
    ? (summary.valid ? `Policy is valid in ${summary.mode} mode.` : `Policy is invalid: ${summary.error}.`)
    : "No .orca/policy.yaml found. Initialize from a preset.";
  els.presetList.innerHTML = policy.presets.map((preset) => `
    <article class="preset-card">
      <h5>${escapeHtml(preset.name)}</h5>
      <p class="caption">${preset.experimental ? escapeHtml(preset.warning) : "Stable local starter policy."}</p>
      <button class="button secondary" type="button" data-preset="${escapeHtml(preset.name)}">Use preset</button>
    </article>
  `).join("");
}

function renderIntegrations(plugins) {
  els.integrationGrid.innerHTML = plugins.map((plugin) => `
    <article class="integration-card">
      <header>
        <h5>${escapeHtml(plugin.label)}</h5>
        <span class="status-pill ${(plugin.host_detected && plugin.integration_present) ? "ok" : "warn"}">
          ${(plugin.host_detected && plugin.integration_present) ? "detected" : "needs setup"}
        </span>
      </header>
      <div class="meta-grid">
        ${meta("Host binary", plugin.host_detected ? "found in PATH" : "not found")}
        ${meta("Orca integration", plugin.integration_present ? "present in repo" : "not found")}
      </div>
      <div class="action-grid">
        ${plugin.setup_commands.map((command) => `<code class="command-line">${escapeHtml(command)}</code>`).join("")}
        <button class="button secondary" type="button" data-action="${plugin.id}-doctor">Run ${escapeHtml(plugin.label)} doctor</button>
      </div>
    </article>
  `).join("");
}

function meta(label, value) {
  return `<div class="meta"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`;
}

async function runAction(action) {
  els.commandOutput.textContent = `Running ${action}...`;
  try {
    const result = await postJson("/api/actions", { action });
    const output = [
      `$ ${action}`,
      `exit ${result.exit_code}`,
      result.stdout || "",
      result.stderr ? `stderr:\n${result.stderr}` : "",
    ].filter(Boolean).join("\n\n");
    els.commandOutput.textContent = output;
    toast(result.ok ? "Command completed" : "Command returned a non-zero result");
    refresh();
  } catch (error) {
    els.commandOutput.textContent = error.message;
    toast(`Command failed: ${error.message}`);
  }
}

async function savePolicy() {
  try {
    const result = await postJson("/api/policy", { text: els.policyText.value });
    if (!result.ok) {
      toast(`Policy not saved: ${result.error}`);
      els.policyHelp.textContent = `Policy not saved: ${result.error}.`;
      return;
    }
    toast("Policy saved");
    refresh();
  } catch (error) {
    toast(`Save failed: ${error.message}`);
  }
}

async function initPreset(preset) {
  try {
    const result = await postJson("/api/policy/init", { preset, force: false });
    if (!result.ok && result.error === "PolicyAlreadyExists") {
      toast("Policy already exists. Save explicit edits from the editor to replace it.");
      return;
    }
    if (!result.ok) {
      toast(`Preset failed: ${result.error}`);
      return;
    }
    toast(`Initialized ${preset}`);
    refresh();
  } catch (error) {
    toast(`Preset failed: ${error.message}`);
  }
}

function toast(message) {
  const node = document.createElement("div");
  node.className = "toast";
  node.textContent = message;
  els.toastRegion.appendChild(node);
  window.setTimeout(() => node.remove(), 4200);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
