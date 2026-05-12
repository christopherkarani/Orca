FROM debian:bookworm-slim

# Aegis Edge package image is for local simulation/SITL/bench-preparation
# evaluation only. It is not real-flight readiness, certification, live
# aircraft control, detect-and-avoid, or autopilot replacement behavior.

RUN useradd --create-home --shell /usr/sbin/nologin aegis
WORKDIR /opt/aegis-edge
COPY bin/aegis-edge /usr/local/bin/aegis-edge
COPY schemas ./schemas
COPY examples/edge ./examples/edge
COPY docs/edge ./docs/edge
USER aegis

ENTRYPOINT ["aegis-edge"]
CMD ["deployment", "doctor"]
