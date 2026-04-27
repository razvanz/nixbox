# 015: No virtiofs for churning caches

**Date:** 2026-04-27
**Status:** accepted

## Problem

`virtiofsd --cache=auto` accumulates backing-file FDs monotonically; under FD-heavy workloads (e.g. `sbt update` validating thousands of `.jar__sha1` files) host shares pin at the process `RLIMIT_NOFILE` ceiling and surface as `ENFILE` in the guest (#18). Raising the limit (PR #20, 524288) buys headroom but doesn't change the monotonicity.

## Decision

Plugins MUST NOT virtiofs-mount churning data — package-manager caches, build-artifact caches, indexer state. Cache I/O lives on `root.img`, which persists per workspace, at the tool's default location (or via env-var redirect from a setup script when the default is not under `$HOME`).

If the host has a useful warm cache to seed the guest with, plugins SHOULD deliver it via a host-side **plugin command** (`plugins/<name>/commands/<cmd>.sh`) invoked from a `post-up` hook. The command streams the cache into the guest over the existing SSH channel (e.g. `tar | nixbox run "tar -x"`) and writes a sentinel for idempotency. No virtiofs mount is involved.

Use virtiofs only where in-place cross-boundary semantics matter (e.g. source trees).

## Rationale

`virtiofsd --cache=auto` holds a backing-file FD per served file and never meaningfully drops them — the FD set grows monotonically with workload. A persistent mount of a churning cache fails on this alone; the constrained atomic-op semantics noted in ADR-001 are an aggravating secondary cost.

A plugin command driven by `post-up` is the right primitive for one-shot host→guest data transfer: it runs host-side where the data is, has the same SSH channel `bin/nixbox` uses internally, and is also user-invocable for manual refreshes (mirroring the established `nixbox aws login` and `nixbox claude-code sync-config` patterns).

## Consequences

- New plugins do not declare runtime mounts for cache paths. Defaults under `$HOME` work; non-`$HOME` defaults get an env-var redirect from `scripts/setup.sh` (plugins cannot inject `env`, per ADR-013).
- Host→guest cache seeding lives in a plugin command, called from `hooks.post-up`. The command is responsible for idempotency.
- Live host↔guest cache sharing is gone; the warmup snapshots host state at first boot, then guest and host diverge.
- `plugins/scala-sbt`: warmup delivered by `nixbox scala-sbt warm-cache` (host-side `tar` piped into the guest). No virtiofs mounts at all in this plugin.

## Future work

VM snapshotting would replace the per-workspace warmup with a pre-warmed image; tracked separately.
