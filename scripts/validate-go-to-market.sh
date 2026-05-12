#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GTM="$ROOT/go_to_market"

required='
README.md
30-day-plan.md
30-day-checklist.md
icp.md
target-account-template.csv
target-account-template.md
qualification-framework.md
landing-page-copy.md
outreach/founder-email-1.md
outreach/founder-email-2-followup.md
outreach/founder-linkedin-message.md
outreach/warm-intro-request.md
outreach/post-demo-followup.md
outreach/pilot-proposal-email.md
calls/discovery-call-script.md
calls/demo-call-script.md
calls/technical-validation-call.md
calls/safety-review-call.md
calls/objections-and-answers.md
pilots/paid-pilot-offer.md
pilots/pilot-pricing-guidance.md
pilots/pilot-close-plan.md
pilots/pilot-mutual-action-plan.md
pilots/pilot-success-scorecard.md
launch/launch-checklist.md
launch/announcement-draft.md
launch/demo-video-script.md
launch/founder-demo-talk-track.md
launch/community-post-draft.md
crm/crm-fields.md
crm/pipeline-stages.md
crm/daily-tracker-template.md
crm/weekly-review-template.md
metrics/acquisition-dashboard.md
metrics/success-metrics.md
safety/safety-claims-guide.md
safety/claims-to-avoid.md
safety/customer-boundary-language.md
targeting/first-50-account-build-guide.md
targeting/customer-safety-filter.md
PHASE_42_OUTPUT_SUMMARY.md
'

for path in $required; do
  test -f "$GTM/$path" || {
    echo "missing go_to_market/$path" >&2
    exit 1
  }
done

python3 - "$GTM" <<'PY'
import pathlib
import re
import sys

gtm = pathlib.Path(sys.argv[1])
text_suffixes = {".md", ".csv", ".sh"}
texts = {p: p.read_text() for p in gtm.rglob("*") if p.is_file() and p.suffix in text_suffixes}

secret_patterns = [
    "BEGIN PRIVATE KEY",
    "ghp_",
    "sk-",
    "AKIA",
]
for path, text in texts.items():
    for pat in secret_patterns:
        if pat in text:
            raise SystemExit(f"secret-like marker found in {path.relative_to(gtm)}: {pat}")

email_re = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
for path, text in texts.items():
    matches = [m.group(0) for m in email_re.finditer(text) if "{{" not in m.group(0)]
    if matches:
        raise SystemExit(f"real-looking email address found in {path.relative_to(gtm)}: {matches[0]}")

claims_allowlist = {
    pathlib.Path("safety/claims-to-avoid.md"),
    pathlib.Path("safety/safety-claims-guide.md"),
    pathlib.Path("safety/customer-boundary-language.md"),
}
positive_banned = [
    "certified safe",
    "guarantees safety",
    "FAA approved",
    "BVLOS-ready",
    "flight-ready",
    "real-flight-ready",
    "replaces autopilot",
    "covers all MAVLink commands",
]
for path, text in texts.items():
    rel = path.relative_to(gtm)
    if rel in claims_allowlist:
        continue
    for phrase in positive_banned:
        if phrase in text:
            raise SystemExit(f"banned overclaim phrase found in {rel}: {phrase}")

offer = texts[gtm / "pilots/paid-pilot-offer.md"]
pricing = texts[gtm / "pilots/pilot-pricing-guidance.md"]
if "Template only - requires legal review" not in offer:
    raise SystemExit("paid-pilot-offer missing legal-review marker")
if "editable/internal guidance" not in offer or "editable/internal guidance" not in pricing:
    raise SystemExit("pricing guidance must be marked editable/internal")

for rel in ["README.md", "outreach/founder-email-1.md", "targeting/first-50-account-build-guide.md"]:
    text = texts[gtm / rel]
    if "automated sender" in text or "scrape private" in text:
        raise SystemExit(f"unsafe outreach automation wording in {rel}")

print("go-to-market validation passed")
PY
