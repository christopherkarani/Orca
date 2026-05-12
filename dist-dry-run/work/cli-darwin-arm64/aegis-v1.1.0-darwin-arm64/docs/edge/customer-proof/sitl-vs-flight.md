# SITL Versus Flight

SITL means simulator-in-the-loop. It can demonstrate policy decisions, command mapping, audit capture, replay, and simulator integration behavior under local test conditions.

SITL does not prove:

- Real aircraft dynamics.
- Real sensors.
- Radio-link behavior.
- Hardware reliability.
- Operator training.
- Airworthiness.
- Real-world flight safety.

Fake adapter tests prove deterministic product behavior. SITL tests prove local simulator behavior. Bench-preparation proves no-actuation preparation behavior. None of these are real-flight evidence.
