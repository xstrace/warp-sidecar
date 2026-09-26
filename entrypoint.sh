#!/bin/sh
set -eu

state_dir=/var/lib/cloudflare-warp
runtime_dir=/run/cloudflare-warp
log_dir=/var/log/cloudflare-warp
machine_id_file="$state_dir/machine-id"

mkdir -p "$state_dir" "$runtime_dir" "$log_dir" /run/dbus /var/lib/dbus

# Registration data and the machine identity belong to one sidecar instance.
# Never mount the same state directory into multiple running WARP containers.
if [ ! -s "$machine_id_file" ]; then
    dbus-uuidgen >"$machine_id_file"
fi
cp "$machine_id_file" /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

dbus-daemon --system --fork --nopidfile

# The daemon appends its full log stream to the console file for the life of
# the container. cron runs the daily logrotate, which caps the file at
# ~50M active plus three compressed archives (see /etc/logrotate.d/warp-console).
cron

export STATE_DIRECTORY="$state_dir"
export RUNTIME_DIRECTORY="$runtime_dir"
export LOGS_DIRECTORY="$log_dir"

# The daemon debug stream may contain registration metadata. Keep it out of
# Docker logs and outside the persistent state volume.
warp-svc >>"$log_dir/warp-svc.console.log" 2>&1 &
warp_pid=$!

cleanup() {
    warp-cli --accept-tos disconnect >/dev/null 2>&1 || true
    kill "$warp_pid" >/dev/null 2>&1 || true
    wait "$warp_pid" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

attempt=0
until warp-cli --accept-tos status >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 60 ]; then
        echo "WARP daemon did not become ready" >&2
        exit 1
    fi
    sleep 1
done

if ! warp-cli --accept-tos registration show >/dev/null 2>&1; then
    echo "Creating anonymous WARP registration"
    warp-cli --accept-tos registration new
fi

warp-cli --accept-tos tunnel protocol set "$WARP_TUNNEL_PROTOCOL"
warp-cli --accept-tos mode "$WARP_MODE"
warp-cli --accept-tos connect

attempt=0
until warp-cli --accept-tos status 2>/dev/null | grep -q 'Connected'; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 90 ]; then
        echo "WARP did not connect" >&2
        warp-cli --accept-tos status >&2 || true
        exit 1
    fi
    sleep 1
done

echo "WARP connected using $WARP_TUNNEL_PROTOCOL in $WARP_MODE mode"
wait "$warp_pid"
