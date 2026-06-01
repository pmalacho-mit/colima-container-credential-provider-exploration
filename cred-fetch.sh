#!/usr/bin/env sh
# cred-fetch.sh — ask the broker for this container's secret.
#
# Run during the TRUSTED init phase (before any agent/untrusted code), then
# wrap your workload so the secret lives only in that process:
#
#     API_KEY="$(cred-fetch.sh)" exec your-agent ...
#
# Needs python3 in the container (most dev images have it). If not, the
# socat equivalent is:  printf '%s' "$BROKER_NONCE" | socat - UNIX-CONNECT:"$SOCK"
set -eu
SOCK="${BROKER_SOCK:-/run/cred-broker.sock}"
NONCE="${BROKER_NONCE:?BROKER_NONCE not set}"

RESP="$(printf '%s' "$NONCE" | python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall(sys.stdin.read().encode())
print(s.recv(4096).decode().strip())
' "$SOCK")"

if [ "$RESP" = "DENIED" ] || [ -z "$RESP" ]; then
  echo "cred-fetch: broker denied or empty response" >&2
  exit 1
fi
printf '%s' "$RESP"
