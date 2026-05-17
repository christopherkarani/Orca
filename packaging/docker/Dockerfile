FROM alpine:3.20

LABEL org.opencontainers.image.title="Orca CI"
LABEL org.opencontainers.image.description="Minimal CI image for running the Zig-built Orca binary."
LABEL org.opencontainers.image.source="https://github.com/christopherkarani/Orca"

RUN apk add --no-cache ca-certificates git bash coreutils

# Release automation should build the Linux amd64 artifact, verify checksums.txt,
# extract bin/orca, and provide it in the Docker build context as ./orca.
COPY orca /usr/local/bin/orca
RUN chmod 0755 /usr/local/bin/orca && orca version

ENTRYPOINT ["orca"]
CMD ["--help"]
