#!/usr/bin/env sh
# cred-install.sh — runs INSIDE the container during trusted init
# (devcontainer.json "onCreateCommand"). Fetches the secret once and exposes
# it to EVERY program in the container, while keeping it out of docker inspect.
#   - value stored on tmpfs (RAM), not the image layer  -> /run/cred/env
#   - sourced by all login shells via /etc/profile.d     -> ambient env
# Cost of "ambient": readable via docker cp/exec/export, so the proxy must deny
# those for this tier. It is NOT in Config.Env, so docker inspect stays clean.
# Needs to run as root (python:3-slim is root; else prefix with sudo).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
NONCE="$(cat "$HERE/.broker-nonce")"
VALUE="$(BROKER_NONCE="$NONCE" BROKER_SOCK=/run/cred-broker.sock sh "$HERE/cred-fetch.sh")"
umask 077
printf '%s\n' "$VALUE" > /run/cred/env       # store your secret as KEY=VAL lines
cat > /etc/profile.d/cred.sh <<'PROF'
set -a; . /run/cred/env; set +a
PROF
rm -f "$HERE/.broker-nonce"
echo "credentials installed for all shells (sourced from /run/cred/env on tmpfs)"
