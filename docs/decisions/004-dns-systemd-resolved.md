# 004: DNS delegation to systemd-resolved

**Date:** 2026-03-24
**Status:** accepted

## Problem

The guest VM needs DNS for both public domains and VPN-internal domains (e.g., a private artifact repository resolving to an internal load balancer IP). The initial plan was to implement split-DNS routing in dnsmasq — detect VPN presence, route VPN queries to the VPN resolver, route public queries to a public resolver.

This would have duplicated logic that already exists in the host's DNS stack.

## Decision

Forward **all** dnsmasq queries to `127.0.0.53` — the systemd-resolved stub resolver:

```
dnsmasq --listen-address=172.16.0.1 --server=127.0.0.53
```

The host's systemd-resolved already handles split-DNS routing. The VPN client (OpenConnect) auto-configures systemd-resolved with per-link DNS servers and search domains. dnsmasq simply delegates to it.

No loop risk: dnsmasq listens on `172.16.0.1` (TAP interface), not localhost, so queries from the guest don't circle back through dnsmasq.

## Consequences

- Guest DNS "just works" with VPN. VPN connect/disconnect after VM boot is transparent — internal domains resolve immediately once the VPN is up, and fail when it's down (matching host behavior).
- No split-DNS logic to maintain in the claudebox codebase.
- Depends on systemd-resolved being the host's DNS resolver. Hosts using other resolvers (e.g., `unbound`, `dnsmasq` directly) would need the `--server=` target adjusted.
- DNS filtering (domain allowlist in filtered mode) is a separate concern layered on top via `--server=/domain/127.0.0.53` per-domain rules.
