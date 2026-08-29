#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

image=warp-sidecar:test
container="warp-sidecar-test-$$"
consumer="$container-consumer"
volume="warp-sidecar-test-state-$$"

cleanup() {
    docker container rm --force "$consumer" >/dev/null 2>&1 || true
    docker container rm --force "$container" >/dev/null 2>&1 || true
    docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build --tag "$image" .
docker volume create "$volume" >/dev/null
docker run --detach \
    --name "$container" \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --device /dev/net/tun:/dev/net/tun \
    --volume "$volume:/var/lib/cloudflare-warp" \
    "$image" >/dev/null

for _ in $(seq 1 45); do
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container")
    if [ "$health" = healthy ]; then
        break
    fi
    if [ "$health" = unhealthy ]; then
        docker logs "$container" >&2
        exit 1
    fi
    sleep 2
done

if [ "${health:-}" != healthy ]; then
    docker logs "$container" >&2
    echo "WARP sidecar did not become healthy" >&2
    exit 1
fi

docker run --detach \
    --name "$consumer" \
    --network "container:$container" \
    --entrypoint /bin/sh \
    "$image" \
    -c 'while :; do sleep 3600; done' >/dev/null

docker exec "$consumer" /bin/sh -c \
    'curl -fsS --max-time 15 https://www.cloudflare.com/cdn-cgi/trace | grep -q "^warp=on$"'

echo "OK: an isolated consumer container exits through WARP"

docker exec "$container" pkill -TERM -x warp-svc

for _ in $(seq 1 15); do
    if [ "$(docker inspect --format '{{.State.Running}}' "$container")" = false ]; then
        break
    fi
    sleep 1
done

if docker exec "$consumer" curl -fsS --max-time 5 https://example.com/ >/dev/null 2>&1; then
    echo "ERROR: consumer reached the Internet after WARP stopped" >&2
    exit 1
fi

echo "OK: consumer fails closed after WARP stops"
