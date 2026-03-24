# 008: Runtime resource patching via sed

**Date:** 2026-03-24
**Status:** accepted

## Problem

VCPUs and RAM are configurable per-project but baked into the Nix derivation at build time. The `nix build` output is a cloud-hypervisor runner script (`microvm-run`) with hardcoded `--cpus boot=N` and `--memory size=NM` flags. Changing resources normally requires a full `nix build` (~30+ seconds).

Resource tuning is the most frequently adjusted setting (e.g., giving an SBT project more RAM), so rebuild latency is painful.

## Decision

Set high headroom ceilings in `flake.nix` (256 vCPUs, 64 GB). At `nixbox up` time, copy the runner script to the run directory and `sed`-patch the resource flags:

```bash
cp "$runner/bin/microvm-run" "$run_dir/microvm-run"
sed -i "s/--cpus boot=[0-9]*/--cpus boot=$vcpus/" "$run_dir/microvm-run"
sed -i "s/--memory size=[0-9]*M/--memory size=${mem_mb}M/" "$run_dir/microvm-run"
```

The patched copy runs instead of the Nix store original.

**vCPUs** default to all host cores (`nproc`). They are KVM threads scheduled by the host — cheap when idle, no reservation.

**Memory** defaults to half of host RAM (minimum 4 GB). Uses virtio-balloon (`microvm.balloon = true` in flake.nix) — the value is a limit, not a reservation. The guest returns unused pages to the host via `free_page_reporting`, and the balloon deflates on OOM so the guest can reclaim up to the limit. The headroom ceiling in flake.nix (64 GB) costs nothing when unused.

## Consequences

- Resource changes take effect on next `nixbox up` — no rebuild needed.
- Headroom ceilings (256 vCPUs, 64 GB) are not reservations. vCPUs are KVM threads (cheap when idle), memory uses balloon (returns unused pages). No cost for unused headroom.
- `nix show-derivation` shows the headroom values, not actual runtime values. This is confusing but acceptable.
- **Fragility:** If cloud-hypervisor changes its CLI flag format (e.g., `--cpus boot=N` becomes `--cpus=boot:N`), the sed patterns silently fail to match and the VM boots with headroom values. This is intentional tech debt — the alternative (per-config Nix rebuilds) is worse for the use case.
