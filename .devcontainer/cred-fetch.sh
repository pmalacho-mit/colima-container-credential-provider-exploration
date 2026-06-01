#!/usr/bin/env sh
# cred-fetch.sh — ask the broker for this container's secret, using curl.
# No python in the container: curl speaks HTTP to the broker's unix socket.
# (curl ships in mcr.microsoft.com/devcontainers/base images. On a barebones
# image, install curl, or use:  socat - UNIX-CONNECT:"$SOCK")
set -eu
SOCK="${BROKER_SOCK:-/run/cred-broker.sock}"
NONCE="${BROKER_NONCE:?BROKER_NONCE not set}"

RESP="$(curl -s --unix-socket "$SOCK" "http://localhost/fetch?nonce=$NONCE")"

if [ "$RESP" = "DENIED" ] || [ -z "$RESP" ]; then
  echo "cred-fetch: broker denied or empty response" >&2
  exit 1
fi
printf '%s' "$RESP"
