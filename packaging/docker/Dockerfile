FROM alpine:3.20

LABEL org.opencontainers.image.title="Aegis CI"
LABEL org.opencontainers.image.description="Minimal CI image for running the Zig-built Aegis binary."
LABEL org.opencontainers.image.source="https://github.com/chriskarani/aegis"

RUN apk add --no-cache ca-certificates git bash coreutils

# Release automation should build the Linux amd64 artifact, verify checksums.txt,
# extract bin/aegis, and provide it in the Docker build context as ./aegis.
COPY aegis /usr/local/bin/aegis
RUN chmod 0755 /usr/local/bin/aegis && aegis version

ENTRYPOINT ["aegis"]
CMD ["--help"]
