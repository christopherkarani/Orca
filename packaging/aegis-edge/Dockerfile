FROM debian:bookworm-slim

RUN useradd --create-home --shell /usr/sbin/nologin aegis
WORKDIR /opt/aegis-edge
COPY bin/aegis-edge /usr/local/bin/aegis-edge
COPY schemas ./schemas
COPY examples/edge ./examples/edge
COPY docs/edge ./docs/edge
USER aegis

ENTRYPOINT ["aegis-edge"]
CMD ["deployment", "doctor"]
