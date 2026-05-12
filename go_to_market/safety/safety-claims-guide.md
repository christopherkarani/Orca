# Safety Claims Guide

## Allowed Language

- "simulation/SITL evidence"
- "policy enforcement in supported scenarios"
- "audit/replay evidence"
- "safety-case report for evaluation"
- "customer-evaluation evidence"
- "fake adapter evidence"
- "bench-preparation/no-actuation review"
- "not certification"
- "not real-flight validation"
- "not autopilot replacement"

## Default Boundary Paragraph

Aegis Edge is customer-evaluation material only. It is limited to simulation/SITL/bench-preparation evaluation and does not include real flight, live aircraft control, certification, regulatory approval, detect-and-avoid, or autopilot replacement.

## Evidence Meaning

- Fake adapter evidence proves deterministic product behavior.
- SITL evidence proves local simulator behavior.
- Bench-preparation evidence is no-actuation preparation.
- None of these are real-flight evidence.

## Artifact Requirements

Every artifact must include provenance, limitations, non-certification language, and no raw secrets.

## Use When Speaking To Customers

- "This shows how Aegis Edge behaved on this supported scenario."
- "This report is useful for engineering review and customer evaluation."
- "Skipped and unsupported results are not passes."
- "Customer-specific commands require explicit mapping."
