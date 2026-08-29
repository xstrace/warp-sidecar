# WARP Sidecar

An isolated Docker sidecar that installs Cloudflare's official Linux WARP
client and gives one application stack a WARP-only network namespace.

This repository builds the container wrapper. It does not compile or replace
Cloudflare WARP: the image installs the official `cloudflare-warp` package from
Cloudflare's Debian repository.

> [!IMPORTANT]
> This is an independent container wrapper, not an official Cloudflare image.
> Cloudflare WARP is not an anonymity service and does not guarantee a chosen
> country or a unique egress IP.

## Why one sidecar per stack?

Reuse the image, not a single running container. Every Compose project starts
its own WARP instance and receives an independent network namespace, port
space, tunnel, registration, and persistent state volume.

```text
ghcr.io/xstrace/warp-sidecar
├── stack A: warp + app A + state A
├── stack B: warp + app B + state B
└── stack C: warp + app C + state C
```

Different stacks may reuse the same container ports. Host-published ports must
still be unique.

## Requirements

- Linux Docker Engine with Compose v2
- `/dev/net/tun` on the Docker host
- Permission to add `NET_ADMIN` and `NET_RAW` to the WARP sidecar
- Outbound access required by the Cloudflare WARP client

The application container receives no extra capabilities.

## Quick start

Copy the relevant services from [`compose.example.yaml`](compose.example.yaml),
or start the example directly:

```bash
docker compose -f compose.example.yaml up -d
docker compose -f compose.example.yaml exec app \
  curl -fsS https://www.cloudflare.com/cdn-cgi/trace
```

The trace must contain:

```text
warp=on
```

The essential application setting is:

```yaml
services:
  app:
    network_mode: service:warp
    depends_on:
      warp:
        condition: service_healthy
```

Docker requires ports to be published by the owner of the shared network
namespace. Put application port mappings on `warp`, not on `app`:

```yaml
services:
  warp:
    ports:
      - "127.0.0.1:8080:8080"
```

Binding to `127.0.0.1` avoids unintentionally exposing the application on every
host interface.

## Isolation rules

- Give every running WARP instance its own state volume.
- Never mount one `/var/lib/cloudflare-warp` volume into two live containers.
- Do not add `privileged: true`, host networking, the Docker socket, or host
  filesystem mounts.
- Do not grant network capabilities to the application container.
- Keep `network_mode: service:warp`; do not add a direct-network fallback.
- Treat containers sharing one WARP sidecar as one trust boundary because they
  also share `localhost` and the TCP/UDP port space.

Named Compose volumes are project-scoped by default, which makes separate
Compose projects safe for multiple simultaneous WARP instances.

## Persistent registration

On first start, the entrypoint creates an anonymous consumer WARP registration.
Registration data and a stable machine ID are stored in:

```text
/var/lib/cloudflare-warp
```

Preserve that volume across image upgrades. Removing it intentionally creates
a new anonymous registration on the next start.

Do not commit, publish, back up to an untrusted location, or share registration
state.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `WARP_TUNNEL_PROTOCOL` | `MASQUE` | Tunnel protocol passed to `warp-cli` |
| `WARP_MODE` | `warp+doh` | Full traffic plus DNS-over-HTTPS mode |

The defaults deliberately route both application traffic and DNS through WARP.
There is no HTTP/SOCKS or host-network fallback.

## Image tags

Images are published to:

```text
ghcr.io/xstrace/warp-sidecar
```

- `latest`: most recent `v*` release
- `1.2.3` and `1.2`: semantic-version release tags
- `edge`: latest successful `main` or scheduled build
- `sha-...`: immutable source revision tag

The workflow builds `linux/amd64` and `linux/arm64`, emits SBOM and provenance
metadata, and creates a GitHub artifact attestation. GitHub Actions are pinned
to commit SHAs.

The weekly `edge` build refreshes the Cloudflare package from the official APT
repository. Release tags change only when a new repository version is tagged.

## Pinning a Cloudflare package version

By default, a new image build installs the latest package offered for Debian
Bookworm. For a controlled build, pass the exact APT version:

```bash
docker build \
  --build-arg CLOUDFLARE_WARP_VERSION='VERSION_FROM_APT' \
  -t warp-sidecar:local .
```

## Local integration test

The test builds the image, creates a temporary registration volume, starts an
isolated WARP instance, checks its health, then verifies a second container in
the same network namespace reports `warp=on`:

```bash
./scripts/integration-test.sh
```

The temporary container and volume are removed automatically.

## Operational checks

```bash
docker compose exec -T warp warp-cli --accept-tos status
docker compose exec -T warp /usr/local/bin/healthcheck.sh
docker compose logs --tail=100 warp
```

The daemon's verbose console output is intentionally kept out of Docker logs
because it may contain registration metadata.

## Updating

Use immutable release tags in production. To upgrade one stack:

```bash
docker compose pull warp
docker compose up -d --force-recreate warp app
```

Recreating `warp` without recreating containers that share its network
namespace can leave consumers attached to the old namespace, so recreate the
consumers at the same time.

## License and upstream

The wrapper files in this repository are licensed under the MIT License.
Cloudflare WARP is proprietary software distributed under Cloudflare's terms.
Installing or using it means accepting the applicable Cloudflare terms.

- [Cloudflare WARP for Linux](https://developers.cloudflare.com/warp-client/get-started/linux/)
- [Cloudflare WARP package repository](https://pkg.cloudflareclient.com/)
- [Docker container network mode](https://docs.docker.com/engine/network/)
