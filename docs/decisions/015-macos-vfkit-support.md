# 015: macOS support via vfkit hypervisor

**Date:** 2026-04-07
**Status:** accepted

## Problem

nixbox was Linux-only (cloud-hypervisor + TAP + nftables + dnsmasq). macOS users — including those on Apple Silicon — could not run nixbox at all. Supporting macOS requires a different hypervisor, networking stack, and several platform-conditional code paths.

## Decision

Add macOS (aarch64-darwin) as a supported host platform using [vfkit](https://github.com/crc-org/vfkit) as the hypervisor and macOS vmnet for networking.

### Platform differences

| Concern | Linux | macOS |
|---|---|---|
| Hypervisor | cloud-hypervisor | vfkit (Virtualization.framework) |
| Networking | TAP + nftables + dnsmasq | vmnet NAT (DHCP from macOS) |
| Guest IP discovery | Static (slot-based `172.16.{slot*4}.2`) | ARP scan after boot |
| Filesystem sharing | virtiofs (virtiofsd) | virtiofs (vfkit built-in) |
| CPU detection | `nproc` | `sysctl -n hw.ncpu` |
| Network filtering | nftables allowlist + dnsmasq DNS | Not yet implemented |
| Hot-plug mounts | cloud-hypervisor HTTP API | Not supported — restart required |
| Credential disk | virtio-blk hot-plug via HTTP API | virtio-blk attached at boot |

### Architecture mapping

Apple tools report `arm64` for the CPU architecture, but Nix uses `aarch64`. The CLI maps `arm64` → `aarch64` in `_nix_system()` to produce correct Nix system triples (e.g. `aarch64-darwin`).

The guest is always `aarch64-linux` regardless of host — darwin hosts run Linux guests via Virtualization.framework's Rosetta support or native ARM execution.

### CI compromise

macOS GitHub Actions runners cannot build `aarch64-linux` derivations (no Linux builder available). Therefore:

- **Unit tests** (ShellCheck, BATS, Nix eval) run on both Linux and macOS — they don't build guest images.
- **E2E tests** (full VM lifecycle) run on Linux only — they require building the NixOS guest rootfs.

macOS E2E testing requires either local hardware or a CI provider with Linux builder support for cross-compilation.

## Consequences

- macOS users on Apple Silicon can run nixbox with `vfkit` as the hypervisor.
- Network filtering (`filtered` mode) is not yet available on macOS — only `open` mode works. Implementing pfctl-based filtering is future work.
- Hot-plug mount/unmount is not supported on macOS — mounts must be declared in config and require a VM restart.
- E2E CI coverage is Linux-only; macOS regressions in the boot path won't be caught until tested locally.
- The `microvm.interfaces` config requires an `id` field for all interface types, even when the ID has no physical meaning (e.g. vfkit user networking).
