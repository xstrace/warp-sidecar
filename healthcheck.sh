#!/bin/sh
set -eu

warp-cli --accept-tos status 2>/dev/null | grep -q 'Connected'
curl -fsS --max-time 10 https://www.cloudflare.com/cdn-cgi/trace \
    | grep -q '^warp=on$'
