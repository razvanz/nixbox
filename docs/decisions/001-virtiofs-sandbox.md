# 001: virtiofs sandbox mode

**Date:** 2026-03-24
**Status:** accepted

## Problem

virtiofsd defaults to `--sandbox=namespace`, which creates a mount+pid namespace and uses credential switching (`setuid`/`setgid`) to serve files as the requesting user. This requires root. When running virtiofsd as a regular user, the credential switching fails silently — every `open()` with `O_CREAT` returns `EINVAL` inside the guest.

Symptoms observed:
- SBT `createFileExclusively` failed with `EINVAL` (JDK `File.createNewFile()`)
- Node.js `writeFileUtf8` failed on virtiofs-backed paths
- Both were initially misdiagnosed as an `O_TMPFILE` problem, leading to a Node.js v20 pin that masked the real issue

strace inside the guest confirmed JDK 25 uses `O_CREAT|O_EXCL` (not `O_TMPFILE`), so the Node.js version was irrelevant.

## Decision

Use `--sandbox=none` on all virtiofsd invocations.

This disables the mount/pid namespace entirely. Since claudebox already provides isolation at the VM level (the guest runs inside cloud-hypervisor), the virtiofsd sandbox is redundant — the host filesystem boundary is enforced by `--shared-dir`, not by the namespace.

The Node.js v20 override in `flake.nix` was reverted since it was a workaround for the misdiagnosed root cause.

## Consequences

- **File creation works** for all guest processes without root on the host.
- **`O_TMPFILE` remains unsupported** on virtiofs regardless of sandbox mode. Tools that use `O_TMPFILE` on virtiofs-backed paths need tmpfs overlays on those directories — this is the user's responsibility via setup scripts.
- **No namespace isolation** inside virtiofsd. Acceptable because the VM boundary is the real security boundary.
