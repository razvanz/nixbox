# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is nixbox

A cloud-hypervisor microVM sandbox for running AI agents in full KVM isolation. Built on Nix flakes + [microvm.nix](https://github.com/astro/microvm.nix). The CLI (`bin/nixbox`) is a ~1000-line Bash script that orchestrates VM lifecycle, networking, and credential injection.

## Build & Development

```bash
# Build the VM runner (NixOS rootfs + cloud-hypervisor config)
nix build .#vm-runner

# Evaluate resolved config (useful for debugging merge logic)
nix eval --impure --json --expr '(import ./lib/resolve.nix { configPath = /path/to/config.nix; pluginsDir = ./plugins; })'

# Full CLI (installed via flake)
nix run .#nixbox -- <command>
```

## Testing

CI runs on every push/PR via `.github/workflows/ci.yml`. Three jobs, all on GitHub-hosted runners (no KVM):

```bash
# ShellCheck — lint all bash scripts (severity: warning+)
shellcheck -x -S warning bin/nixbox lib/functions.bash plugins/*/commands/*.sh plugins/*/scripts/*.sh

# BATS unit tests — pure function tests (derive_network, parse_mount_spec, slots, find_nixbox_dir)
nix shell nixpkgs#bats --command bats tests/unit/
# or: bash tests/run-unit-tests.sh

# Nix eval tests — config resolution with fixture configs
bash tests/run-nix-tests.sh
```

Shared bash functions live in `lib/functions.bash` (sourced by `bin/nixbox`). New pure/testable logic should go there with corresponding BATS tests in `tests/unit/`.

## Architecture

### VM Lifecycle (`nixbox up` → `nixbox down`)

1. **Config resolution** — `lib/resolve.nix` deep-merges defaults → plugins (in order) → user config. Lists concatenate; attrsets deep-merge; scalars: user wins.
2. **Build** — Nix builds a cloud-hypervisor runner + NixOS rootfs. Result cached via content hash in `.nixbox/state/.build-hash`.
3. **Slot allocation** — MD5 of `.nixbox/` absolute path → slot 0–63. Determines TAP device (`vmN`), IP space (`172.16.{slot*4}.0/30`), vsock CID (`3+slot`), nftables table (`nixbox_{name}`).
4. **Launch** — sed-patches the runner script for vCPUs/RAM/TAP, starts virtiofsd instances, launches cloud-hypervisor.
5. **Hot-plug** — Credentials ext4 disk + virtiofs mounts attached via cloud-hypervisor HTTP API.
6. **Guest boot** — systemd oneshot `inject-env` reads credential disk → `~/.env`, then SSH becomes available.
7. **Teardown** — graceful shutdown, cleanup nftables/dnsmasq/virtiofsd/TAP, release slot.

### Network Modes

- `off` — DHCP only, all forwarding dropped
- `filtered` (default) — DNS allowlist (suffix-matched via dnsmasq) + port whitelist (default: 80, 443)
- `open` — full NAT

### Plugin System

Plugins live in `plugins/{name}/default.nix`. They declare packages, mounts, domains, scripts, hooks. Plugin commands live in `plugins/{name}/commands/*.sh`. Env var injection from plugins is explicitly forbidden (ADR-013).

### Credential Flow

User config declares env vars (via `builtins.getEnv`) → serialized to ext4 image → hot-plugged as virtio-blk → guest systemd oneshot extracts to `~/.env` → sourced on shell login.

## Key Constraints

- **virtiofs does not support `O_TMPFILE`** — tools that use it (e.g., Claude Code telemetry dirs) need tmpfs overlays. See ADR-001.
- **Max 64 concurrent VMs** — slot space is hardcoded.
- **Runtime patching** — vCPUs, RAM, TAP device are sed-patched into the Nix-built runner script at launch (ADR-008). Don't assume the runner script is used as-built.
- **Root required** — dnsmasq and TAP/nftables setup require sudo.
- **SSH uses `-T` (no TTY)** when stdin is piped (non-interactive `nixbox run`). Only `nixbox shell` gets a TTY.

## Code Conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, etc. Scope optional but encouraged.
- Bash: the CLI uses `set -euo pipefail`. Shared functions are in `lib/functions.bash`. `cmd_` functions are CLI command handlers; `do_` functions are internal VM operations.
- Nix: no fully qualified paths in code — import symbols and use short names.

## ADRs

Architecture decisions are in `docs/decisions/`. Read these before changing networking, credential injection, virtiofs config, or plugin semantics.
