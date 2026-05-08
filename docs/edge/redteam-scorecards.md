# Edge Red-Team Scorecards

Every red-team run writes scorecard artifacts under the selected output
directory:

- `scorecard.md`
- `scorecard.json`
- `replay.md`

When `--report safety-case` is supplied, the run also writes:

- `safety-report.md`
- `safety-report.json`

Human output groups results by category and prints required fake/simulation pass
math. JSON output includes run id, audit session id, fixture id, category,
environment, result, point totals, expected and actual decisions, expected and
actual findings, expected and actual events, forbidden-log status, safety-case
report path, skip or unsupported reason, and limitations.

Scoring rules:

- Required passed fixtures earn their configured points.
- Required failed or inconclusive fixtures count against possible points.
- Skipped and unsupported fixtures do not earn points and are not pass.
- Optional PX4/ArduPilot SITL fixtures are reported separately from fake fixtures.

The scorecard is engineering evidence only. It does not claim real-flight
readiness, certification, detect-and-avoid, autopilot replacement behavior, or
regulatory approval.
