# 015: Don't virtiofs-mount churning cache directories

**Date:** 2026-04-27
**Status:** accepted

## Problem

Plugins have been mounting host package-manager caches (`~/.cache/coursier`, `~/.ivy2`) via virtiofs to share warm state with the host. Under FD-heavy workloads — `sbt update` validating hundreds of `.jar__sha1` entries in parallel, or any LRU-shaped cache traversal — `virtiofsd --cache=auto` accumulates backing-file FDs monotonically across the session and pins shares at the process `RLIMIT_NOFILE` ceiling. Host `EMFILE` surfaces in the guest as `ENFILE` ("Too many open files in system"), failing builds even when the guest has FDs to spare (#18).

Raising the limit (PR #20, 65536 → 524288) buys headroom but doesn't change the monotonic accumulation. A long enough session hits the new ceiling.

## Decision

Plugins MUST NOT virtiofs-mount directories that churn under LRU-shaped access — package-manager caches, build-artifact caches, indexer state, log directories. Cache state lives on the guest's `root.img` (which persists per workspace across `up`/`down`) at the tool's default location; if the tool's default is not under `$HOME`, redirect via the relevant env var from a setup script.

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

For tools whose default cache lives under `$HOME`, the simplest implementation is to *not mount* — the default already lands on `root.img`.

Virtiofs continues to be the right choice for source trees and similar shares with moderate file count where in-place semantics matter (host editor and guest tool reading the same files). Sensitive data uses dedicated explicit channels: credentials via the one-shot ext4 disk (ADR-003), VM SSH identity via per-VM key injection (ADR-014). Plugins that mount additional host state (e.g. claude-code's `~/.claude`, ADR-010) own the tradeoff in their own ADR.

## Rationale

Virtiofs has two costs that scale with workload, not share size:

1. **`virtiofsd` holds backing-file FDs for every file it serves under `--cache=auto`.** The high-water mark grows monotonically across a long session; LRU caches with thousands of small files (`.jar__sha1`) hit the ceiling fastest.
2. **Cross-boundary semantics for atomic operations are constrained vs. native fs** (see ADR-001 on `O_TMPFILE`). Package managers rely on rename atomicity and tmpfile semantics for partial-write cleanup.

A churning cache fails both tests: many small files, and the tool relies on filesystem invariants. Putting it on virtiofs provides no semantic value (the cache is a derived artifact, not a source of truth) and pays the ongoing FD cost.

The host-cache-sharing argument — "I want my IDE outside the VM to use the same jars" — is real but trades a one-time re-download per workspace against a soft architectural ceiling. The trade-off favors guest-native: `root.img` keeps the cache warm within a workspace, and the user's bandwidth amortizes a fresh download once.

## Consequences

- New plugins do not declare `mounts` for cache paths. Tools either pick up defaults under `$HOME` or get redirected via env vars from `scripts/setup.sh` (since plugins cannot inject `env`, per ADR-013).
- Users lose live host↔guest cache sharing. First fetch per workspace re-downloads.
- `plugins/scala-sbt` migrated in this PR: drops `~/.cache/coursier` and `~/.ivy2` mounts. Coursier's default `~/.cache/coursier` and ivy2's default `~/.ivy2/` land on `root.img` automatically.
- A future `nixbox doctor` lint can flag plugins mounting common cache paths.

## Future work

VM snapshotting (cold disk clone via qcow2 backing file, or live save/restore via cloud-hypervisor's HTTP API) would make the warmup cost disappear: a "blessed" warm image starts new VMs in seconds with caches pre-populated. This is a separate, larger feature; the decision above is the immediate fix.
