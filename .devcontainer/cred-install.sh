#!/usr/bin/env sh
# cred-install.sh — runs INSIDE the container at first create (onCreateCommand).
# Fetches the secret once and exposes it to EVERY program, while keeping it out
# of docker inspect. Works as the non-root devcontainer user (e.g. 'vscode'):
#   - the tmpfs at /run/cred is owned by this user (see runArgs uid/gid)
#   - writing /etc/profile.d needs root, so that one line uses sudo
# Cost of "ambient": readable via docker cp/exec/export, so the proxy must deny
# those for this tier. It is NOT in Config.Env, so docker inspect stays clean.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
NONCE="$(cat "$HERE/.broker-nonce")"
VALUE="$(BROKER_NONCE="$NONCE" BROKER_SOCK=/run/cred-broker.sock sh "$HERE/cred-fetch.sh")"

umask 077
printf '%s\n' "$VALUE" > /run/cred/env          # store secrets as KEY=VAL lines
echo 'set -a; . /run/cred/env; set +a' | sudo tee /etc/profile.d/cred.sh >/dev/null

rm -f "$HERE/.broker-nonce"
echo "credentials installed for all shells (sourced from /run/cred/env on tmpfs)"
