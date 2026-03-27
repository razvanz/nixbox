# 014: Inject VM SSH key for outbound authentication

**Date:** 2026-03-27
**Status:** accepted

## Problem

The VM needs to authenticate to external SSH hosts (GitHub, private Git servers) from inside the guest. Three options were considered:

1. **SSH agent forwarding** — forward `$SSH_AUTH_SOCK` from host into guest via `-A`.
2. **Separate outbound key** — generate a second key pair inside the guest on first boot.
3. **Inject the existing VM key** — copy the nixbox-generated private key (`vm_key`) into `~/.ssh/id_ed25519` at boot.

## Decision

Inject the existing VM key (`vm_key`) into `~/.ssh/id_ed25519` during `nixbox up`, after SSH is ready.

Agent forwarding was rejected: it leaks the host's key material into a guest that may run untrusted agents with `--dangerously-skip-permissions`. A compromised agent could use the forwarded socket to authenticate as the user on any service.

A separate outbound key was rejected: it requires an extra generation step, produces a key with no stable location on the host, and creates a second identity the user must manage.

Using the existing `vm_key` is safe: nixbox already manages this key, it's scoped to the `.nixbox/` directory, and it's never shared between VMs. The private key is transmitted over the already-established SSH session (host to guest), so no additional trust boundary is crossed.

## Consequences

- The VM can authenticate to GitHub and other SSH hosts using its own stable identity.
- Users add `vm_key.pub` to GitHub once (personal key or deploy key); all subsequent boots work without reconfiguration.
- The key is regenerated only when `.nixbox/ssh/vm_key` is deleted — this invalidates any GitHub authorization and requires re-adding the key.
- The private key is present on the guest filesystem. This is acceptable: the guest is already trusted, and the key has no broader host-level access.
