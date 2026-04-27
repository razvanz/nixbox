# 015: Avoid virtiofs for churning caches

**Date:** 2026-04-27
**Status:** accepted

## Problem

`virtiofsd --cache=auto` accumulates backing-file FDs monotonically. Under churning workloads (`sbt update`, package-manager refreshes), shares pin at `RLIMIT_NOFILE` and surface as `ENFILE` in the guest (#18). Raising the ceiling (PR #20) doesn't change the trajectory.

## Decision

In-tree plugins do not virtiofs-mount churning data — package-manager caches, build-artifact caches, indexer state. Cache I/O lives on `root.img` (persists per workspace) at the tool's default location, or via env-var redirect from a setup script.

When useful host warm-cache state exists, in-tree plugins deliver it via a host-side **plugin command** invoked from `post-up` — the pattern of `nixbox aws login` and `nixbox claude-code sync-config`. Streams over the existing SSH channel (`tar | nixbox run "tar -x"`); sentinel-guarded.

Third-party plugins are not bound. Authors who virtiofs-mount churning caches accept the FD cost — any long enough session will exhaust the ceiling. The plugin-command pattern is one alternative, not the only one.

Use virtiofs only where in-place cross-boundary semantics matter (e.g. source trees).

## Consequences

- `plugins/scala-sbt`: warmup via `nixbox scala-sbt warm-cache`. No virtiofs mounts.
- Host↔guest cache sharing is one-shot, not live: warmup snapshots host state at first boot, then guest and host diverge.

## Possible direction

VM snapshotting (qcow2 backing or cloud-hypervisor save/restore) could replace the per-workspace warmup with a pre-warmed image. Not committed work — noted as one way this trade-off might be revisited.
