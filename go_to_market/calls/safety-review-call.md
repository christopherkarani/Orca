# Safety Review Call

## Objective

Confirm the customer understands the evidence boundary, non-goals, and pilot safety constraints before proposal or kickoff.

## Opening

"This review is about making sure the pilot evidence is useful and not overstated. Edge can support simulation/SITL/bench-preparation evaluation. It does not provide aircraft validation, approval, detect-and-avoid, or replacement of your safety process."

## Review Topics

- Evaluation environment.
- No-actuation boundary.
- Supported scenarios.
- Unsupported scenarios.
- Evidence artifacts.
- Limitations language.
- Data handling and redaction.
- Operator approval assumptions.
- Emergency behavior assumptions.
- Customer safety owner.

## Required Confirmations

- The pilot starts in fake adapter, SITL, or no-actuation bench-preparation.
- No raw secrets are needed.
- No private customer data is needed.
- Skipped, unsupported, and inconclusive results are reported as such.
- Safety-case evidence is for evaluation only.
- Customer keeps responsibility for safety process and approval path.

## Close

"If these boundaries are acceptable, the next step is the mutual action plan and pilot kickoff."
