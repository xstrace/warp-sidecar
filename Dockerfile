ARG DEBIAN_IMAGE=debian:bookworm-slim
FROM ${DEBIAN_IMAGE}

ARG CLOUDFLARE_WARP_VERSION=""

LABEL org.opencontainers.image.title="WARP Sidecar" \
      org.opencontainers.image.description="Isolated Cloudflare WARP sidecar for Docker workloads" \
      org.opencontainers.image.source="https://github.com/xstrace/warp-sidecar" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    WARP_MODE=warp+doh \
    WARP_TUNNEL_PROTOCOL=MASQUE

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        gnupg \
        iproute2 \
        nftables \
        tini \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" \
        > /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update \
    && if [ -n "$CLOUDFLARE_WARP_VERSION" ]; then \
        apt-get install -y --no-install-recommends "cloudflare-warp=$CLOUDFLARE_WARP_VERSION"; \
       else \
        apt-get install -y --no-install-recommends cloudflare-warp; \
       fi \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/machine-id \
    && touch /etc/machine-id

COPY entrypoint.sh healthcheck.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

HEALTHCHECK --interval=15s --timeout=12s --start-period=30s --retries=6 \
    CMD ["/usr/local/bin/healthcheck.sh"]

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
