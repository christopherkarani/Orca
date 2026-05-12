# Aegis Edge Watchdog

The watchdog policy is a local policy section used to configure heartbeat max ages, telemetry freshness, audit writer requirements, degraded-mode behavior, and lightweight resource limits. CI and strict contexts fail closed when required audit persistence or safety-policy health is unavailable.

The watchdog never bypasses command policy or the safety envelope. Deny beats allow. Emergency LAND, RTH, and HOLD remain policy-controlled and require the required context such as home position or position/control state.

This is not real-flight readiness, not autopilot replacement behavior, not hosted telemetry, not an external network dependency, and not regulatory certification.
