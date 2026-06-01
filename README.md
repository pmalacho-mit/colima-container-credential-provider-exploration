# colima-container-credential-provider-exploration

A devcontainer setup for macOS that runs on [Colima](https://github.com/abiosoft/colima)
(no Docker Desktop, no license, no external service) and gives each container its
own credentials, scoped so that one container cannot read another's secrets — even
though containers can start other containers.

This is a security **scaffold / proof of concept** meant for evaluation. It is not
yet production-hardened (see [Limitations](#limitations)).

## What it does

- Runs containers in a Colima VM whose only host mount is your repos folder, so a
  container escape is limited to your source code rather than your whole machine.
- Hands each container a secret fetched at launch, kept out of `docker inspect`.
- Authenticates *which* container is asking by the kernel-attested container id
  (`SO_PEERCRED` → `/proc/<pid>/cgroup`), so re-mounting another container's broker
  socket gets you nothing.
- Stores the actual secrets in the **local macOS Keychain** — nothing sensitive is
  written to disk inside the VM.

## What's in here

```
.
├─ README.md
├─ colima-secure.yaml         # Colima profile: restricted mount + broker (host setup)
├─ test.sh                    # end-to-end verification (run from the host)
├─ cred-broker.py             # reference copy of the broker (the live copy is
│                             #   embedded in colima-secure.yaml — see note below)
└─ .devcontainer/
   ├─ devcontainer.json
   ├─ dc-initialize.sh        # runs on the HOST before the container is created
   ├─ cred-install.sh         # runs IN the container at first create
   └─ cred-fetch.sh           # helper used by cred-install.sh (uses curl)
```

> `cred-broker.py` is reference only. The broker that actually runs is embedded in
> `colima-secure.yaml`'s provision block. Edit the `.py` if you like, then paste it
> back into the YAML.

## Prerequisites

- macOS (the setup uses Colima and the macOS Keychain)
- [Homebrew](https://brew.sh)
- VS Code with the **Dev Containers** extension
- `openssl` and `security` are built into macOS — nothing to install

The devcontainer image must ship `curl` and `sudo`. The default image here,
`mcr.microsoft.com/devcontainers/base:ubuntu-24.04`, includes both and runs as a
non-root `vscode` user; if you swap images, see [Customizing](#customizing).

## Setup (once per machine)

### 1. Install Colima and the Docker CLI

```sh
brew install colima docker
```

(`docker` here is just the CLI; Colima provides the engine. No Docker Desktop.)

### 2. Create the `secure` profile

Edit the `mounts:` line in `colima-secure.yaml` to point at **your** repos parent
folder, then place the config and start the profile:

```sh
mkdir -p ~/.colima/secure
cp colima-secure.yaml ~/.colima/secure/colima.yaml
colima start secure
```

First start downloads the VM image and runs provisioning (installs the broker),
so it takes a couple of minutes. If `colima start` doesn't pick up the file, use
`colima start secure --edit` and paste the contents instead.

> **Provisioning runs only at VM creation.** If you change the provision block
> later, recreate the VM: `colima delete secure` then `colima start secure`.

Confirm the broker came up:

```sh
colima ssh secure -- systemctl is-active cred-broker     # -> active
```

### 3. Put a test secret in your Keychain

Store secrets as `KEY=VALUE` lines (one or several) under the service name
`devcred-<name>`:

```sh
security add-generic-password -a "$USER" -s "devcred-secret_A" -w
# when prompted, paste e.g.:   API_KEY=test-value-12345
```

## Verify the security property

`test.sh` is self-contained (it registers literal test values, no Keychain needed)
and proves the core guarantee, including the attack. The test client uses a raw
HTTP request from a tiny `python:3-slim` container so it needs nothing extra; your
real devcontainer uses `curl`. Both hit the same broker. Run it after the profile
is up:

```sh
./test.sh
```

Expected output:

```
1) A fetches its own secret (binds nonce A to container A):
  PASS: A receives secret_A
2) ATTACK: B has A's socket mounted and replays A's nonce:
  PASS: B is refused A's secret
3) B fetches its own secret:
  PASS: B receives secret_B

result: 3 passed, 0 failed
```

Step 2 is the point: container B successfully mounted A's broker socket — the
re-mount attack worked at the filesystem level — and was still refused, because
the broker checks the caller's container id, not who can reach the socket.

## Use it from VS Code

1. Pin VS Code to the profile so the container lands in the right VM (the active
   Docker context is global, so be explicit):

   ```sh
   docker context use colima-secure
   ```

2. Make sure your repo lives under the mounted folder (e.g. `~/code/repos/...`),
   open it in VS Code, and run **Dev Containers: Reopen in Container**.

VS Code runs `dc-initialize.sh` on the host (mints a one-time nonce, reads the
secret from your Keychain, registers it with the broker), then `cred-install.sh`
inside the container fetches the secret once with `curl` and exposes it to every
shell. The container runs as the non-root `vscode` user.

3. In a container terminal, confirm the credential is available to programs:

   ```sh
   echo "$API_KEY"        # -> test-value-12345
   ```

   And confirm it is NOT exposed to the Docker API from outside (run on the host):

   ```sh
   docker --context colima-secure inspect <container> \
     --format '{{json .Config.Env}}'    # the secret does NOT appear here
   ```

## How it works

Three layers, each independent:

**Blast-radius mount.** The profile mounts only your repos folder into the VM, so a
container escape sees your source code and nothing else on your Mac. The mount is
recursive — nested repos at any depth work, and are all equally inside that radius.

**Per-container identity.** The broker runs in the VM and listens on a unix socket
mounted into each container. On every request it reads the caller's kernel-attested
container id (`SO_PEERCRED` → `/proc/<pid>/cgroup`) and a one-time nonce that the
trusted host launcher registered. The nonce binds to the first container id that
presents it; any other id is refused. So reachability of the socket is not access.

**Secret delivery.** The host resolves the secret from the Keychain and registers
the value with the broker over a root-only control socket; the broker holds it only
in memory. The container fetches it during trusted init — `curl` over the broker's
HTTP unix socket, no python in the container — and writes it to a tmpfs file sourced
by all shells. Available to every program, but kept out of `docker inspect`.

## Customizing

- **Repos location:** change `mounts:` in `colima-secure.yaml`.
- **Which secret a repo gets:** change `secret_A` in `devcontainer.json`'s
  `initializeCommand`, and store a matching `devcred-<name>` Keychain entry.
- **Multiple variables:** store several `KEY=VALUE` lines in one Keychain entry;
  they all become environment variables in the container.
- **Different devcontainer image:** keep it one that ships `curl` and `sudo`. If its
  default user isn't uid/gid 1000, update the `--tmpfs /run/cred:...uid=,gid=` values
  in `devcontainer.json` to match (run `id` inside the container to check). To run as
  root instead, add `"remoteUser": "root"` and you can drop the `uid=`/`gid=` options.
- **Different trust tiers:** run a second profile (`colima start <other>`) with a
  different mount and its own broker for containers that need more or less access.

## Limitations

- macOS only (Keychain + Colima-on-Mac).
- Assumes Colima's default Ubuntu/systemd VM. An Alpine guest needs the service
  installed via OpenRC instead of systemd.
- The broker's registry is in memory — restarting the broker (or the VM) drops
  registrations; just re-launch the container to re-register.
- This is the secret-isolation half only. The companion piece is a Docker-socket
  proxy that prevents a container from creating privileged children or bind-mounting
  the broker socket, and denies `docker cp`/`exec`/`export` for this tier (which is
  what would otherwise read the ambient secret file). Without it, the broker's
  identity check is still the backstop, but defense-in-depth is incomplete.

## Troubleshooting

- **`broker not active`** — the profile was likely created before the config was in
  place, so provisioning didn't run. `colima delete secure` and recreate. Inspect
  logs with `colima ssh secure -- journalctl -u cred-broker`.
- **Fetch returns `DENIED`** — the nonce wasn't registered, or the container is in a
  different VM than expected, or the cgroup id didn't parse. Check the cgroup format
  with `colima ssh secure -- cat /proc/1/cgroup` (the broker matches a 64-hex id).
- **`$API_KEY` is empty in a terminal** — `/etc/profile.d` is sourced by login
  shells, so open a fresh terminal. `cred-install.sh` writes that file with `sudo`,
  which needs the container user to have passwordless sudo (the `vscode` user in the
  base image does). And the tmpfs at `/run/cred` must be owned by the container user
  — see the `uid=`/`gid=` note under [Customizing](#customizing).
- **`curl: command not found` during create** — your image doesn't ship curl; add it
  (e.g. a devcontainer feature, or `apt-get install -y curl` in `onCreateCommand`
  before the fetch), or use the default base image.
- **Container lands in the wrong VM** — you didn't pin the context; run
  `docker context use colima-secure` before reopening.
- **`security: ... could not be found`** — seed the Keychain first (step 3); the
  account is `$USER` and the service is `devcred-<name>`.
