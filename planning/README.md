# Local planning artifacts

This directory is **gitignored** except for this README. Agents and contributors should put
session-local planning here instead of the repository root or `docs/`.

## What belongs here

- Agent handoffs, review TODOs, and orchestration notes
- Migration plans, architecture drafts, and comparison write-ups
- Prompt exports, task prompts, and exploration memos
- Generated evidence, scratch notes, and one-off investigation output

## What does **not** belong here

- Shipped product code, tests, or schemas
- Public documentation meant for users (`docs/`, `README.md`, `CHANGELOG.md`)
- Tracked protocol or architecture docs the team has explicitly approved for the repo
  (for example `docs/plans/UDS_PROTOCOL_v1.md`)

## Suggested layout

```
planning/
  migration/     # merge plans, phase maps, gap registers
  handoffs/      # session handoffs between agents
  reviews/       # PR/issue review notes and TODO lists
  comparisons/   # protocol/command/build comparisons
  prompts/       # agent prompts and task briefs
  exploration/   # codebase recon and spike notes
  scratch/       # empty files, one-off dumps, disposable output
```

Do not commit contents of this tree unless the user explicitly asks to publish a specific file.
