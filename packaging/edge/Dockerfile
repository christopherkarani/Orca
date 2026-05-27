FROM debian:bookworm-slim

# Edge package image is for local simulation/SITL/bench-preparation
# evaluation only. It is not real-flight readiness, certification, live
# aircraft control, detect-and-avoid, or autopilot replacement behavior.
# Verify the source artifact checksum before building this image.

RUN useradd --create-home --shell /usr/sbin/nologin edge
WORKDIR /opt/edge
COPY bin/edge /usr/local/bin/edge
COPY schemas ./schemas
COPY examples/edge ./examples/edge
COPY docs/edge ./docs/edge
USER edge

ENTRYPOINT ["edge"]
CMD ["deployment", "doctor"]
