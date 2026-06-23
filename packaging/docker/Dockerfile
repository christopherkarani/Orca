FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54

LABEL org.opencontainers.image.title="Orca CI"
LABEL org.opencontainers.image.description="Orca CLI, daemon, and runtime resources for CI."
LABEL org.opencontainers.image.source="https://github.com/christopherkarani/Orca"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git bash coreutils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 orca

# Release automation must verify the archive checksum and extract the complete Linux release root,
# then provide that directory in the Docker build context as ./orca.
COPY orca /opt/orca
ENV PATH="/opt/orca/bin:${PATH}"
ENV ORCA_RESOURCE_ROOT="/opt/orca"
RUN test -x /opt/orca/bin/orca \
    && test -x /opt/orca/bin/orca-daemon \
    && test -d /opt/orca/policies \
    && test -d /opt/orca/schemas \
    && /opt/orca/bin/orca version

USER orca
WORKDIR /home/orca
ENTRYPOINT ["orca"]
CMD ["--help"]
