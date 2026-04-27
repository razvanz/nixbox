# 015: No steady-state virtiofs for churning caches

**Date:** 2026-04-27
**Status:** accepted

## Problem

Plugins have been mounting host package-manager caches (`~/.cache/coursier`, `~/.ivy2`) via virtiofs as the runtime read/write path. Under FD-heavy workloads — `sbt update` validating hundreds of `.jar__sha1` entries in parallel, or any LRU-shaped cache traversal — `virtiofsd --cache=auto` accumulates backing-file FDs monotonically across the session and pins shares at the process `RLIMIT_NOFILE` ceiling. Host `EMFILE` surfaces in the guest as `ENFILE` ("Too many open files in system"), failing builds even when the guest has FDs to spare (#18).

Raising the limit (PR #20, 65536 → 524288) buys headroom but doesn't change the monotonic accumulation. A long enough session hits the new ceiling.

## Decision

Plugins MUST NOT use virtiofs as the **steady-state runtime path** for churning data — package-manager caches, build-artifact caches, indexer state, log directories. Runtime cache I/O lives on the guest's `root.img` (which persists per workspace across `up`/`down`) at the tool's default location. If the default is not under `$HOME`, redirect via the relevant env var from a setup script.

Reference table for common toolchains:

| Tool                     | Default location          | Env var                      |
| ------------------------ | ------------------------- | ---------------------------- |
| sbt / coursier           | `~/.cache/coursier`       | `COURSIER_CACHE`             |
| ivy2                     | `~/.ivy2/`                | (default works)              |
| npm / pnpm / yarn        | `~/.npm`, `~/.pnpm-store` | `npm_config_cache`, `…`      |
| pip / uv                 | `~/.cache/pip`            | `PIP_CACHE_DIR`              |
| cargo                    | `~/.cargo`                | `CARGO_HOME`                 |
| go modules               | `~/go/pkg/mod`            | `GOMODCACHE`                 |
| docker storage           | `/var/lib/docker`         | (already guest-native)       |

### Bootstrap exception

A read-only virtiofs mount at a side path used for a one-shot copy into `root.img` during the setup script is permitted. Once warmup completes, the mount stops being accessed and the runtime tool I/O lives entirely on `root.img`. The `virtiofsd` FD high-water mark is bounded by the number of files copied (one-time peak), not by session length — typical coursier caches yield ~50–100k FDs, comfortably under the 524288 ceiling.

Bootstrap mounts MUST:
- Be marked `readonly = true`.
- Mount at a side path (e.g. `/mnt/host-cache/coursier`), never at the tool's runtime cache location.
- Be read by an idempotent setup script that writes a sentinel and skips re-runs.
- Not be touched after the warmup completes (no live host↔guest cache sharing).

### What stays on virtiofs

Virtiofs continues to be the right choice for source trees and similar shares with moderate file count where in-place semantics matter (host editor and guest tool reading the same files). Sensitive data uses dedicated explicit channels: credentials via the one-shot ext4 disk (ADR-003), VM SSH identity via per-VM key injection (ADR-014). Plugins that mount additional host state (e.g. claude-code's `~/.claude`, ADR-010) own the tradeoff in their own ADR.

## Rationale

Virtiofs has two costs that scale with workload, not share size:

1. **`virtiofsd` holds backing-file FDs for every file it serves under `--cache=auto`.** The high-water mark grows monotonically with use.
2. **Cross-boundary semantics for atomic operations are constrained vs. native fs** (see ADR-001 on `O_TMPFILE`). Package managers rely on rename atomicity and tmpfile semantics for partial-write cleanup.

A steady-state churning cache fails both tests: many small files, and the tool relies on filesystem invariants. The bootstrap pattern accepts the first cost briefly (one rsync pass, bounded by file count) to retain a useful property — first-build is fast because the host's warm cache transfers in. Steady-state cache I/O then runs against `root.img` with no virtiofs involvement.

The host-cache-sharing argument — "I want my IDE outside the VM to use the same jars" — is partially preserved by bootstrap: the guest gets the host's current cache state at workspace creation, then diverges. Live cross-boundary sharing is given up; one-time seeding plus per-workspace persistence is enough in practice.

## Consequences

- New plugins do not declare runtime mounts for cache paths. Defaults under `$HOME` work as-is; non-`$HOME` defaults get an env-var redirect from `scripts/setup.sh` (since plugins cannot inject `env`, per ADR-013).
- Plugins MAY declare RO bootstrap mounts at side paths and rsync from them in the setup script.
- Users lose live host↔guest cache sharing. First boot per workspace warms the cache from host; subsequent boots use `root.img` directly.
- `plugins/scala-sbt` adopts the bootstrap pattern in this PR: RO mounts at `/mnt/host-cache/coursier` and `/mnt/host-cache/ivy2`, rsynced into `~/.cache/coursier` and `~/.ivy2` on first boot, sentinel-guarded for idempotency. The plugin adds `rsync` to its packages.
- A future `nixbox doctor` lint can flag plugins that mount cache paths at runtime locations (rather than side paths).

## Future work

VM snapshotting (cold disk clone via qcow2 backing file, or live save/restore via cloud-hypervisor's HTTP API) would make even the bootstrap cost disappear: a "blessed" warm image starts new VMs in seconds with caches pre-populated, and replaces the rsync entirely. This is a separate, larger feature; the decision above is the immediate fix.
