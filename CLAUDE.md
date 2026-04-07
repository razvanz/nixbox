# CLAUDE.md

## What is nixbox

A cloud-hypervisor microVM sandbox for running AI agents in full KVM isolation. Built on Nix flakes + [microvm.nix](https://github.com/astro/microvm.nix). The CLI (`bin/nixbox`) is a ~1000-line Bash script that orchestrates VM lifecycle, networking, and credential injection.

## Build & Development

```bash
nix build .#vm-runner        # Build VM runner (NixOS rootfs + cloud-hypervisor config)
nix run .#nixbox -- <command> # Run CLI from source
nix eval --impure --json --expr '(import ./lib/resolve.nix { configPath = /path/to/config.nix; pluginsDir = ./plugins; })' # Debug config resolution
```

## Testing

CI runs on every push/PR via `.github/workflows/ci.yml` (no KVM required):

```bash
shellcheck -x -S warning bin/nixbox lib/functions.bash plugins/*/commands/*.sh plugins/*/scripts/*.sh
nix shell nixpkgs#bats --command bats tests/unit/
bash tests/run-nix-tests.sh
```

New pure/testable logic goes in `lib/functions.bash` with BATS tests in `tests/unit/`.

## Architecture

### VM Lifecycle (`nixbox up` → `nixbox down`)

1. **Config resolution** — `lib/resolve.nix` deep-merges defaults → plugins → user config. Lists concatenate; attrsets deep-merge; scalars: user wins.
2. **Build** — Nix builds cloud-hypervisor runner + NixOS rootfs. Cached via content hash in `.nixbox/state/.build-hash`.
3. **Slot allocation** — MD5 of `.nixbox/` path → slot 0–63. Determines TAP device, IP space (`172.16.{slot*4}.0/30`), vsock CID, nftables table.
4. **Launch** — sed-patches runner script for vCPUs/RAM/TAP (ADR-008), starts virtiofsd, launches cloud-hypervisor.
5. **Hot-plug** — Credentials ext4 disk + virtiofs mounts via cloud-hypervisor HTTP API.
6. **Guest boot** — systemd oneshot reads credential disk → `~/.env`, then SSH available.
7. **Teardown** — graceful shutdown, cleanup nftables/dnsmasq/virtiofsd/TAP, release slot.

### Network Modes

- `off` — DHCP only, all forwarding dropped
- `filtered` (default) — DNS allowlist (suffix-matched via dnsmasq) + port whitelist (default: 80, 443)
- `open` — full NAT

### Plugin System

Plugins in `plugins/{name}/default.nix` declare packages, mounts, domains, scripts, hooks. Commands in `plugins/{name}/commands/*.sh`. Env var injection from plugins forbidden (ADR-013).

### Credential Flow

User config env vars (`builtins.getEnv`) → ext4 image → hot-plugged virtio-blk → guest systemd oneshot → `~/.env` → sourced on login.

## Key Constraints

- **virtiofs does not support `O_TMPFILE`** — needs tmpfs overlays (ADR-001).
- **Max 64 concurrent VMs** — slot space hardcoded.
- **Runtime patching** — vCPUs/RAM/TAP sed-patched into runner at launch (ADR-008).
- **Root required** — dnsmasq and TAP/nftables setup need sudo.
- **SSH uses `-T`** when stdin is piped (`nixbox run`). Only `nixbox shell` gets a TTY.

## Code Conventions

- Bash: `set -euo pipefail`. Shared functions in `lib/functions.bash`. `cmd_` = CLI handlers; `do_` = internal VM ops.
- Nix: no fully qualified paths in code — import symbols and use short names.

## Commits & Releases

This project uses [conventional commits](https://www.conventionalcommits.org/) to drive automated semver tagging and GitHub Releases (`.github/workflows/release.yml`).

- **Prefix every commit** with a type: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`, `ci:`, etc. Scope is optional but encouraged, e.g. `fix(ssh):`.
- **Version bumps** are derived from commit messages since the last tag:
  - `fix:` → patch bump (e.g. `v0.1.0` → `v0.1.1`)
  - `feat:` → minor bump (e.g. `v0.1.1` → `v0.2.0`)
  - `BREAKING CHANGE:` in the commit body or `!` after the type (e.g. `feat!:`) → major bump
- **Releases are automatic**: every push to `main` triggers the release workflow, which tags and creates a GitHub Release with auto-generated notes from merged PRs.
- Commits that don't match any conventional commit type get a **patch** bump by default.

## ADRs

Architecture decisions are in `docs/decisions/`. Read these before changing networking, credential injection, virtiofs config, or plugin semantics.
