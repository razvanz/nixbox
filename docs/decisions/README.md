# Architecture Decision Records

Lightweight records of decisions and hard-won findings that are easy to forget or re-investigate.

## Format

Each file: `NNN-short-title.md` with sections **Problem**, **Decision**, **Consequences**.

## Index

| # | Title | Date | Status |
|---|-------|------|--------|
| [001](001-virtiofs-sandbox.md) | virtiofs sandbox mode | 2026-03-24 | accepted |
| [002](002-virtiofs-uid-gid-mapping.md) | virtiofs UID/GID mapping | 2026-03-24 | accepted |
| [003](003-credential-injection.md) | Credential injection via explicit env var passthrough | 2026-03-24 | accepted |
| [004](004-dns-systemd-resolved.md) | DNS delegation to systemd-resolved | 2026-03-24 | accepted |
| [005](005-docker-forward-chain.md) | Docker FORWARD chain breaks VM networking | 2026-03-24 | accepted |
| [006](006-dns-network-filtering.md) | DNS-based network filtering | 2026-03-24 | accepted |
| [007](007-dnsmasq-user-root.md) | dnsmasq --user=root | 2026-03-24 | accepted |
| [008](008-runtime-resource-patching.md) | Runtime resource patching via sed | 2026-03-24 | accepted |
| [009](009-tap-multi-queue.md) | TAP multi_queue for cloud-hypervisor | 2026-03-24 | accepted |
| [010](010-claude-oauth-session.md) | Sharing Claude OAuth session with the guest | 2026-03-24 | accepted |
| [011](011-guest-setup-scripts.md) | Guest setup via user-provided scripts | 2026-03-24 | accepted |
| [012](012-per-workspace-nixbox-directory.md) | Per-workspace `.nixbox/` directory | 2026-03-24 | accepted |
| [013](013-plugin-env-transparency.md) | Plugins must not inject env vars | 2026-03-24 | accepted |
| [014](014-vm-ssh-key-injection.md) | Inject VM SSH key for outbound authentication | 2026-03-27 | accepted |
| [015](015-macos-vfkit-support.md) | macOS support via vfkit hypervisor | 2026-04-07 | accepted |
