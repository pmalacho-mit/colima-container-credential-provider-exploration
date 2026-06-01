#!/usr/bin/env bash
# test.sh — confirm the broker's identity attestation holds. Self-contained:
# registers literal test values (no Keychain needed) and runs the attack.
# The test client uses a raw HTTP request over python (so the tiny test image
# needs no curl); the real devcontainer uses curl. Both hit the same broker.
# Run AFTER `colima start secure`.
set -uo pipefail
PROFILE="${PROFILE:-secure}"
export DOCKER_HOST="unix://$HOME/.colima/$PROFILE/docker.sock"
SOCK="/run/cred-broker/client.sock"
IMG="python:3-slim"

pass=0; fail=0
check() { case "$3" in "$2"*) echo "  PASS: $1"; pass=$((pass+1));; *) echo "  FAIL: $1 (got: '$3')"; fail=$((fail+1));; esac; }
cleanup() { docker rm -f cA cB >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

colima ssh "$PROFILE" -- systemctl is-active --quiet cred-broker \
  || { echo "broker not active; is the '$PROFILE' profile started?"; exit 1; }

docker run -d --name cA -v "$SOCK:/run/cred-broker.sock" "$IMG" sleep 600 >/dev/null
docker run -d --name cB -v "$SOCK:/run/cred-broker.sock" "$IMG" sleep 600 >/dev/null

fetch() { docker exec "$1" python3 -c 'import socket,sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.connect("/run/cred-broker.sock")
s.sendall(("GET /fetch?nonce="+sys.argv[1]+" HTTP/1.0\r\n\r\n").encode())
d=b""
while True:
    c=s.recv(4096)
    if not c: break
    d+=c
print(d.split(b"\r\n\r\n",1)[-1].decode().strip())' "$2"; }

NA="$(openssl rand -hex 16)"; NB="$(openssl rand -hex 16)"
printf 'value-for-A-AAAA1111' | colima ssh "$PROFILE" -- sudo cred-broker-ctl register "$NA" >/dev/null
printf 'value-for-B-BBBB2222' | colima ssh "$PROFILE" -- sudo cred-broker-ctl register "$NB" >/dev/null

echo; echo "1) A fetches its own secret (binds nonce A to container A):"
check "A receives secret_A" "value-for-A" "$(fetch cA "$NA")"
echo "2) ATTACK: B has A's socket mounted and replays A's nonce:"
check "B is refused A's secret" "DENIED" "$(fetch cB "$NA")"
echo "3) B fetches its own secret:"
check "B receives secret_B" "value-for-B" "$(fetch cB "$NB")"
echo; echo "result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
