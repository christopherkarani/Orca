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
  secretlessState: document.querySelector("#secretlessState"),
  secretlessCommandInput: document.querySelector("#secretlessCommandInput"),
  secretlessRunCommand: document.querySelector("#secretlessRunCommand"),
  copySecretlessRunButton: document.querySelector("#copySecretlessRunButton"),
  insertSecretlessPolicyButton: document.querySelector("#insertSecretlessPolicyButton"),
  secretlessBrokerMeta: document.querySelector("#secretlessBrokerMeta"),
  secretlessPolicyTemplate: document.querySelector("#secretlessPolicyTemplate"),
  secretlessVerifyCommands: document.querySelector("#secretlessVerifyCommands"),
  secretlessCredentialRefs: document.querySelector("#secretlessCredentialRefs"),
  secretlessProxyMeta: document.querySelector("#secretlessProxyMeta"),
  secretlessBrokerChecks: document.querySelector("#secretlessBrokerChecks"),
  secretlessCapabilities: document.querySelector("#secretlessCapabilities"),
  secretlessBrokerGrid: document.querySelector("#secretlessBrokerGrid"),
  secretlessAuditEvents: document.querySelector("#secretlessAuditEvents"),
  secretlessGuarantees: document.querySelector("#secretlessGuarantees"),
  secretlessLimitations: document.querySelector("#secretlessLimitations"),
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
els.secretlessCommandInput.addEventListener("input", updateSecretlessRunCommand);
els.copySecretlessRunButton.addEventListener("click", copySecretlessRunCommand);
els.insertSecretlessPolicyButton.addEventListener("click", insertSecretlessPolicyTemplate);

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
    renderSecretless(status.secretless_runtime);
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
  const secretless = data.secretless_runtime;
  const license = data.license;
  const ci = data.ci_readiness;
  const blockedCount = data.blocked_actions.length;
  const sessionCount = data.sessions.length;
  els.summaryGrid.innerHTML = [
    metric("CLI", "Installed", `Orca ${data.orca.version}`),
    metric("Policy", policy.exists ? (policy.valid ? "Valid" : "Invalid") : "Missing", policy.exists ? policy.path : "Create one from a preset"),
    metric("Secretless", secretless.available ? "Available" : "Unavailable", `${secretless.active_broker.label}: references only`),
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

function renderSecretless(secretless) {
  const broker = secretless.active_broker;
  els.secretlessState.textContent = secretless.available ? "available" : "unavailable";
  els.secretlessState.className = `status-pill ${secretless.available ? "ok" : "bad"}`;
  updateSecretlessRunCommand();

  els.secretlessBrokerMeta.innerHTML = [
    meta("Active broker", broker.label),
    meta("Kind", broker.kind || broker.id),
    meta("Mode", broker.status),
    meta("Stores raw secrets", broker.stores_raw_secrets ? "yes" : "no"),
    meta("Credential injection", broker.injects_raw_credentials ? "enabled" : "not enabled"),
  ].join("");

  els.secretlessPolicyTemplate.textContent = secretless.service_policy_template;
  els.secretlessVerifyCommands.innerHTML = secretless.verify_commands.map((command) => `
    <code class="command-line">${escapeHtml(command)}</code>
  `).join("");

  const refs = secretless.credential_refs || [];
  els.secretlessCredentialRefs.innerHTML = refs.length ? refs.map((item) => `
    <article class="table-row">
      <div>
        <strong>${escapeHtml(item.name)}</strong>
        <span class="caption">${escapeHtml(item.broker || "default broker")}</span>
      </div>
      <code>${escapeHtml(item.ref)}</code>
      <span class="status-pill ok">redacted</span>
    </article>
  `).join("") : `<div class="timeline-item"><h5>No refs declared</h5><p class="caption">Add credentials.refs in .orca/policy.yaml to map services to external broker refs.</p></div>`;

  const proxy = secretless.proxy_backend || {};
  els.secretlessProxyMeta.innerHTML = [
    meta("Status", proxy.status || "unavailable"),
    meta("Backend", proxy.backend || "decision-only"),
    meta("Bind", proxy.bind || "allocated per run"),
    meta("HTTPS visibility", proxy.https_visibility || "host-port-only"),
    meta("Method/path visibility", proxy.method_path_visibility || "http-and-cooperative-hooks"),
  ].join("");

  const checks = secretless.broker_checks || [];
  els.secretlessBrokerChecks.innerHTML = checks.length ? checks.map((item) => `
    <article class="broker-card">
      <header>
        <h5>${escapeHtml(item.broker)}</h5>
        <span class="status-pill ${item.status === "available" || item.status === "limited" ? "ok" : "warn"}">${escapeHtml(item.status)}</span>
      </header>
      <div class="meta-grid">
        ${meta("Kind", item.kind)}
      </div>
      <p class="caption">${escapeHtml(item.message)}</p>
    </article>
  `).join("") : `<div class="timeline-item"><h5>No broker checks</h5><p class="caption">No configured brokers were found in the current policy.</p></div>`;

  els.secretlessCapabilities.innerHTML = secretless.capabilities.map((capability) => `
    <article class="capability-card">
      <header>
        <h5>${escapeHtml(capability.label)}</h5>
        <span class="status-pill ${capability.state === "active" ? "ok" : "warn"}">${escapeHtml(capability.state)}</span>
      </header>
      <p class="caption">${escapeHtml(capability.detail)}</p>
    </article>
  `).join("");

  els.secretlessBrokerGrid.innerHTML = secretless.supported_brokers.map((item) => `
    <article class="broker-card">
      <header>
        <h5>${escapeHtml(item.label)}</h5>
        <span class="status-pill ${item.status === "available" ? "ok" : "warn"}">${escapeHtml(item.status)}</span>
      </header>
      <div class="meta-grid">
        ${meta("Adapter id", item.id)}
        ${meta("Raw storage", item.stores_raw_secrets ? "yes" : "no")}
      </div>
      <p class="caption">${escapeHtml(item.notes)}</p>
    </article>
  `).join("");

  const auditEvents = secretless.recent_audit_events || [];
  els.secretlessAuditEvents.innerHTML = auditEvents.length ? auditEvents.map((item) => `
    <article class="timeline-item">
      <h5>${escapeHtml(item.event_type)}</h5>
      <p class="caption">${escapeHtml(item.target)}</p>
      <div class="meta-grid">
        ${meta("Decision", item.decision || "recorded")}
        ${meta("Verified", item.verified ? "yes" : "not checked")}
      </div>
    </article>
  `).join("") : `<div class="timeline-item"><h5>No recent evidence</h5><p class="caption">Run a secretless proxy session to populate request-level audit events.</p></div>`;

  els.secretlessGuarantees.innerHTML = secretless.guarantees.map((item) => `<li>${escapeHtml(item)}</li>`).join("");
  els.secretlessLimitations.innerHTML = secretless.limitations.map((item) => `<li>${escapeHtml(item)}</li>`).join("");
}

function updateSecretlessRunCommand() {
  const command = els.secretlessCommandInput.value.trim() || "<agent-command>";
  els.secretlessRunCommand.textContent = `orca run --secretless --network-backend proxy -- ${command}`;
}

async function copySecretlessRunCommand() {
  updateSecretlessRunCommand();
  const value = els.secretlessRunCommand.textContent;
  try {
    await navigator.clipboard.writeText(value);
    toast("Secretless run command copied");
  } catch (_) {
    els.commandOutput.textContent = value;
    toast("Copy unavailable; command moved to output");
  }
}

function insertSecretlessPolicyTemplate() {
  if (!state.status?.secretless_runtime?.service_policy_template) return;
  const template = state.status.secretless_runtime.service_policy_template;
  const current = els.policyText.value.trimEnd();
  if (hasGithubServicePolicy(current)) {
    els.policyHelp.textContent = "Policy already contains services.github. Edit the existing service rule instead of inserting a duplicate.";
    showView("policy");
    els.policyText.focus();
    toast("services.github already exists");
    return;
  }
  const separator = current.length > 0 ? "\n\n" : "";
  els.policyText.value = `${current}${separator}${template}\n`;
  els.policyHelp.textContent = "Secretless service policy inserted. Validate and save to persist it.";
  showView("policy");
  els.policyText.focus();
}

function hasGithubServicePolicy(text) {
  const lines = text.split(/\r?\n/);
  let inServices = false;
  let servicesIndent = -1;
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const indent = line.search(/\S/);
    if (trimmed === "services:") {
      inServices = true;
      servicesIndent = indent;
      continue;
    }
    if (inServices && indent <= servicesIndent) {
      inServices = false;
    }
    if (inServices && indent > servicesIndent && trimmed === "github:") return true;
  }
  return false;
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
