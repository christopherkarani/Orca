Edge session: 2026-05-08T20-22-14Z_0c01
Session: 2026-05-08T20-22-14Z_0c01
Command: aegis-edge redteam
Policy: edge-redteam
Status: exit 0
20:22:14  edge.session_start     2026-05-08T20-22-14Z_0c01
20:22:14  edge.scenario_start     audit-redaction-mavlink-marker
20:22:14  mavlink.frame_invalid     audit-redaction-mavlink-marker
20:22:14  edge.scenario_exit     passed
20:22:14  edge.scenario_start     audit-redaction-request-marker
20:22:14  safety.evaluation_started     audit-redaction-request-marker
20:22:14  safety.finding_created     audit-redaction-request-marker
20:22:14  vehicle.command_requested     audit-redaction-request-marker
20:22:14  safety.geofence_violation     audit-redaction-request-marker
20:22:14  vehicle.command_denied     audit-redaction-request-marker
20:22:14  safety.evaluation_completed     audit-redaction-request-marker
20:22:14  edge.scenario_exit     passed
20:22:14  safety_case.evidence_collected     [REDACTED:secret:high_entropy:sha256:195346a4]
20:22:14  edge.session_exit     2026-05-08T20-22-14Z_0c01

Hash chain: verified
Limitations: simulation/SITL/bench-preparation/customer-evaluation evidence only; no real-flight or certification claim.
