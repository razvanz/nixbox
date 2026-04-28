# 016: virtiofsd file-handle mode via setcap'd wrapper

**Date:** 2026-04-27
**Status:** accepted

## Problem

ADR-015 keeps churning caches off virtiofs, but long-lived shares (source trees) still leak FDs under sustained access. `virtiofsd --cache=auto` retains an O_PATH FD per cached inode; with mandatory file-handle mode the cache holds opaque handles instead, freeing the FD slot until the next I/O. This is the only mitigation that addresses the underlying accumulation rather than its symptoms (#18).

`--inode-file-handles=mandatory` calls `name_to_handle_at(2)`, which requires `CAP_DAC_READ_SEARCH`. Without it, virtiofsd refuses to start (`Refusing to use (mandatory) file handles, as they do not appear safe to use`). Today the daemon runs as the host user (UID 1000) under `--sandbox=none` (ADR-001) with no special privileges, so the call returns `EPERM`.

Three privilege models were considered:

1. **Run as root, `--sandbox=none`.** Rejected: with no sandbox there is no per-request `setresuid`, so guest-created files end up owned by root on the host filesystem. Regresses ADR-002.
2. **Run as root, `--sandbox=namespace`.** Rejected: requires the daemon to run as root for one syscall path, and the interaction between namespace credential switching and `--translate-uid` is unverified — no upside over option 4, and any deviation regresses ADR-002. (ADR-001 only proves the *non-root* failure mode, so it doesn't apply here.)
3. **Run as root, `--sandbox=chroot`.** Same root-EUID-on-create problem as option 1.
4. **Grant only `CAP_DAC_READ_SEARCH` on the binary.** Daemon stays at UID 1000; ADR-001 and ADR-002 hold; only the one capability needed by `name_to_handle_at(2)` is added.

## Decision

Option 4. `lib/functions.bash::ensure_virtiofsd_cap` keeps a setcap'd copy of virtiofsd at `${XDG_DATA_HOME:-~/.local/share}/nixbox/bin/virtiofsd` and returns its path; `do_create` and `do_mount` invoke that path with `--inode-file-handles=mandatory`.

`mandatory` over `prefer` because silent fallback to FD-mode would re-introduce the leak with no signal — the failure mode of #18 only surfaces after a long session, exactly the kind of degradation that hides until something OOMs.

A copy under `$XDG_DATA_HOME` rather than `setcap` on the in-store binary, because the host is not NixOS: `/nix/store` is read-only and GC-collectable, `security.wrappers` doesn't apply, and host-package wrappers (`/usr/local/bin`) drift independently of the bundled CLI. A nixbox-managed copy is reinstalled automatically when the source binary realpath changes (e.g., after `nixbox update`), keyed by a sidecar marker file.

`cmd_doctor` reports wrapper status; `nixbox up` triggers (re)install on demand. The first run prompts for sudo (one-time per virtiofsd version), parallel to the existing `sudo prlimit` path in `raise_nofile`.

## Consequences

- The FD ceiling is no longer a function of cache size. Source-tree shares are stable across long sessions.
- **Memory replaces FDs as the long-run ceiling.** Each cached inode now holds an opaque handle in virtiofsd's address space instead of an O_PATH FD. Empirically, ~8 KB per `/nix/store` inode and ~60 KB per workspace inode of virtiofsd RSS. A 524k-inode cache is no longer hitting `RLIMIT_NOFILE`, but it is GBs of resident memory.
- One additional sudo prompt on first `nixbox up` after install or after a virtiofsd version bump.
- **`/proc/<virtiofsd-pid>/fd` is now root-owned.** File capabilities trigger `PR_SET_DUMPABLE=0`, so debugging tools (`lsof -p`, `ls /proc/<pid>/fd`) need sudo. They silently return empty results without it.
- ADR-001 (sandbox=none) and ADR-002 (uid/gid translate) preserved unchanged.
- The granted capability is scoped: `CAP_DAC_READ_SEARCH` bypasses DAC for read/search only, and only matters for paths the daemon already opens via `--shared-dir`. Other DAC checks remain.
- Wrapper drift: invoking nixbox under a non-canonical PATH that resolves a different virtiofsd causes a reinstall. Acceptable — the CLI is a Nix wrapper with a deterministic PATH, so the canonical path is stable.
