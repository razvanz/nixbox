# 009: TAP multi_queue required by cloud-hypervisor

**Date:** 2026-03-24
**Status:** accepted

## Problem

The default `ip tuntap add dev vmtap0 mode tap` creates a single-queue TAP device. cloud-hypervisor's virtio-net implementation expects multi-queue support. With a single-queue TAP, networking *mostly works* but drops packets under load — the failure mode is subtle and hard to reproduce, manifesting as intermittent connection resets or stalled downloads.

Most TAP setup examples online omit the `multi_queue` flag, making this easy to miss.

## Decision

Create the TAP device with multi-queue enabled:

```bash
sudo ip tuntap add dev vmtap0 mode tap multi_queue user "$(whoami)"
```

## Consequences

- Reliable networking under load (large `nix build` downloads, parallel `npm install`, etc.).
- All firewall/NAT rules work identically on multi-queue TAP devices.
- The `user "$(whoami)"` flag allows the non-root virtiofsd and cloud-hypervisor processes to use the TAP device.
