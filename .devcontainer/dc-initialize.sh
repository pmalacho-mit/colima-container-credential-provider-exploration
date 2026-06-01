#!/usr/bin/env bash
# dc-initialize.sh — VS Code runs this ON THE HOST before creating the
# container (devcontainer.json "initializeCommand"). It is the trusted seam.
#   - mint a one-time nonce
#   - read the secret from the local Keychain
#   - register value->nonce with the broker over the VM control socket
#   - stash the nonce where the container will read it (gitignore this file)
# Usage: dc-initialize.sh <profile> <secret-name>
set -euo pipefail
PROFILE="${1:?}"; SECRET="${2:?}"
NONCE="$(openssl rand -hex 16)"
security find-generic-password -a "$USER" -s "devcred-$SECRET" -w \
  | colima ssh "$PROFILE" -- sudo cred-broker-ctl register "$NONCE"
mkdir -p .devcontainer
printf '%s' "$NONCE" > .devcontainer/.broker-nonce
