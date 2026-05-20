# Orca Agent Instructions

## Public Repository Hygiene

- Treat this repository as a public-facing GitHub repo by default.
- Do not track private planning, marketing, GTM, customer-pilot, founder-led sales, launch-ops, release-draft, generated evidence, or local agent task files.
- Keep these surfaces local-only unless the user explicitly asks to publish a specific artifact:
  - `go_to_market/`
  - `customer_pilot/`
  - `tasks/`
  - `reports/`
  - `.orca-edge/`
  - `.edge/`
  - `dist/`
  - `dist-dry-run/`
  - `docs/release/`
  - `docs/orca_opencode_openclaw_plan/`
  - `integrations/**/node_modules/`
- Before staging or committing, run a tracked-file hygiene check for private/public-boundary leaks:
  - `git ls-files | rg '(^go_to_market/|^customer_pilot/|^tasks/|^reports/|^\\.orca-edge/|^\\.edge/|^dist/|^dist-dry-run/|^docs/release/|^docs/orca_opencode_openclaw_plan/|node_modules/)'
- If that command returns any files, stop and untrack them before proceeding.
- Never commit generated release archives, SBOMs, checksums, dry-run package output, red-team replay output, customer-pilot templates, SOW/NDA notes, target-account templates, outreach copy, pricing guidance, or task-memory logs.

## Workflow

- Preserve user-owned dirty changes. Do not revert unrelated edits.
- Use TDD for non-trivial code changes: write or update focused tests before implementation when practical.
- Keep changes surgical and tied to the user request.
- Verify before calling work complete. For code changes, run the narrowest meaningful test first, then broader checks when the blast radius justifies it.
- For audits, lead with concrete file-backed findings and avoid speculative cleanup.

## Product Boundary

- Keep public Core/Orca surfaces separate from internal Orca Edge, customer acquisition, and pilot-planning collateral.
- Public docs may explain supported behavior, installation, security model, and verified limitations.
- Internal docs may plan launches, pilots, pricing, outreach, target accounts, release operations, or founder/customer strategy, but those stay untracked unless explicitly approved for publication.
