# P11 — ClawHub Submission Prep

## Objective

Prepare the Orca OpenClaw plugin for ClawHub submission.

At the end of this phase, the plugin should be ready for:

```bash
clawhub package publish your-org/your-plugin --dry-run
```

and later:

```bash
openclaw plugins install clawhub:orca
```

---

## Recommended Effort

```text
Medium
```

Use High only if ClawHub validation reveals package issues.

---

## Scope

Implement:

- ClawHub submission metadata
- ClawHub dry-run docs
- final OpenClaw README polish
- install docs
- validation checklist
- no actual publishing unless explicitly requested

---

## Non-goals

Do not publish to ClawHub automatically unless explicitly authorized.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not add SaaS or telemetry.

---

## Docs

Create or update:

```text
docs/integrations/openclaw-clawhub.md
```

Include:

- prerequisite: OpenClaw plugin package exists
- prerequisite: npm package metadata valid
- dry-run command
- publish command
- post-publish install command
- verification commands
- known limitations

Example:

```bash
clawhub package publish chriskarani/orca-openclaw-plugin --dry-run
clawhub package publish chriskarani/orca-openclaw-plugin
openclaw plugins install clawhub:orca
openclaw plugins list --json
openclaw plugins doctor
```

Adjust package name to real ClawHub naming convention before publishing.

---

## Package Validation

Run or document:

```bash
npm pack --dry-run ./integrations/openclaw-plugin
```

If `clawhub` CLI is installed:

```bash
clawhub package publish ./integrations/openclaw-plugin --dry-run
```

Do not run the real publish command unless explicitly told.

---

## Release Notes

Update:

```text
PLUGIN_RELEASE_NOTES.md
LAUNCH_PLUGINS.md
docs/integrations/openclaw.md
```

Before actual ClawHub acceptance, say:

```text
ClawHub submission is prepared but not yet published.
```

After acceptance, update to:

```text
openclaw plugins install clawhub:orca
```

---

## Tests

Add checks for:

- ClawHub docs exist
- docs do not claim publication before it happens
- npm package still validates
- no secrets
- no MCP behavior
- no drone behavior

---

## Acceptance Criteria

- ClawHub prep docs exist.
- dry-run command is documented.
- publish command is documented but not run automatically.
- release notes are honest.
- no official ClawHub claim unless actually published.
- existing tests pass.

---

## Deliverable

Create or update:

```text
docs/integrations/p11-clawhub-submission.md
```

Include:

- summary
- dry-run status
- publish status
- docs updated
- known limitations
- whether ClawHub submission is ready

---

## Handoff

At the end, provide:

- files changed
- tests run
- ClawHub dry-run status
- publish status
- known limitations
- manual actions required
