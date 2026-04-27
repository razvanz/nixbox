# 015: No steady-state virtiofs for churning caches

**Date:** 2026-04-27
**Status:** accepted

## Problem

`virtiofsd --cache=auto` accumulates backing-file FDs monotonically; under FD-heavy workloads (e.g. `sbt update` validating thousands of `.jar__sha1` files) host shares pin at the process `RLIMIT_NOFILE` ceiling and surface as `ENFILE` in the guest (#18). Raising the limit (PR #20, 524288) buys headroom but doesn't change the monotonicity.

## Decision

Plugins MUST NOT use virtiofs as the **steady-state runtime path** for churning data — package-manager caches, build-artifact caches, indexer state. Runtime cache I/O lives on `root.img`, which persists per workspace, at the tool's default location (or via env-var redirect from a setup script when the default is not under `$HOME`).

Use virtiofs only where in-place cross-boundary semantics matter (e.g. source trees).

### Bootstrap exception

A read-only virtiofs mount used for a one-shot copy into `root.img` during the setup script is permitted. The FD high-water mark is bounded by the file count copied (one-time peak), not by session length.

Bootstrap mounts MUST:
- Be `readonly = true`.
- Mount at a side path (e.g. `/mnt/host-cache/coursier`), never at the tool's runtime cache location.
- Be read by an idempotent setup script that writes a sentinel and skips re-runs.
- Not be touched after warmup (no live host↔guest cache sharing).

## Rationale

`virtiofsd --cache=auto` holds a backing-file FD per served file and never meaningfully drops them — the FD set grows monotonically with workload. A persistent mount of a churning cache fails on this alone; the constrained atomic-op semantics noted in ADR-001 are an aggravating secondary cost. Bootstrap mounts pay the FD cost once (bounded by file count), then go quiet.

## Consequences

- New plugins do not declare runtime mounts for cache paths. Defaults under `$HOME` work; non-`$HOME` defaults get an env-var redirect from `scripts/setup.sh` (plugins cannot inject `env`, per ADR-013).
- Plugins MAY declare RO bootstrap mounts at side paths and rsync from them in setup.
- Live host↔guest cache sharing is gone; first boot per workspace warms from host, subsequent boots use `root.img` directly.
- `plugins/scala-sbt` adopts the bootstrap pattern: RO mounts at `/mnt/host-cache/{coursier,ivy2}`, rsynced into `~/.cache/coursier` and `~/.ivy2` on first boot, sentinel-guarded. Adds `rsync` to its packages.

## Future work

VM snapshotting would replace the bootstrap rsync with a pre-warmed image; tracked separately.
