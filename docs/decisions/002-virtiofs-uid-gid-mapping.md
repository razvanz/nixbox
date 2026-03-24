# 002: virtiofs UID/GID mapping

**Date:** 2026-03-24
**Status:** accepted

## Problem

NixOS assigns the VM user (matching the host username) UID 1000 and GID 100 (`users` group). On the host, the UID is typically 1000 but the GID varies (e.g., 1000 on most distros, different on others). Without explicit mapping:

- **UID:** worked by coincidence — guest UID 1000 happened to match host UID 1000
- **GID:** files created on virtiofs shares were owned by GID 100 on the host, which is typically `users` but not the host user's primary group

This caused permission mismatches on shared directories. The GID mapping was added first (`--translate-gid`), but UID mapping was missing — it only worked because the UIDs coincidentally matched.

## Decision

All virtiofsd invocations use both flags:

```
--translate-uid="map:1000:$(id -u):1" --translate-gid="map:100:$(id -g):1"
```

- Guest UID 1000 → host user's UID (resolved at runtime via `$(id -u)`)
- Guest GID 100 → host user's GID (resolved at runtime via `$(id -g)`)
- The `:1` suffix means "map exactly 1 ID" (not a range)

This applies to all three virtiofsd instances: nix-store share, user mounts (at boot), and hot-added mounts.

## Consequences

- Files created by the guest appear owned by the host user, regardless of whether host UID/GID is 1000/1000.
- Only one guest user is mapped. If the VM ever runs multiple users, additional mappings would be needed.
- The mapping is one-directional per ID. Guest root (UID 0) is not mapped and will appear as `nobody` on the host, which is the desired behavior.
