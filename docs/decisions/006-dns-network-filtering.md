# 006: DNS-based network filtering (domain allowlist)

**Date:** 2026-03-24
**Status:** accepted

## Problem

The sandboxed VM needs to reach external services but block arbitrary egress. Defaults are minimal (`nixos.org` for Nix cache); users add domains as needed via `.nixbox/config.nix`. Two approaches:

1. **IP-level firewall** — maintain allowlists of IP addresses/ranges per service
2. **DNS-level filtering** — only resolve allowed domains, block everything else at DNS

## Decision

Filter at DNS level. In `filtered` network mode, dnsmasq is configured with per-domain forwarding rules:

```
--server=/github.com/127.0.0.53
--server=/npmjs.org/127.0.0.53
```

Domains not in the allowlist have no `--server=` rule, so dnsmasq returns **SERVFAIL** (not a timeout). The nftables rules only allow DNS traffic (UDP/TCP port 53) to the host gateway and optionally specific TCP ports for services like Docker registries.

## Consequences

- **SERVFAIL vs timeout:** Blocked domains fail immediately instead of hanging for 30+ seconds. This is important for tools like `npm` that try multiple registries — fast failure on blocked ones prevents long stalls.
- **CDN-friendly:** Domain-level filtering handles rotating IPs, CDN edge nodes, and load balancers transparently. IP-level allowlists would require constant updates.
- **Bypassable:** Hardcoded IPs (e.g., `curl 1.2.3.4`) bypass DNS filtering entirely. This is an accepted tradeoff — the sandbox model trusts the code being run to use DNS, not hardcoded IPs.
- **Suffix matching:** dnsmasq's `--server=/github.com/` matches `github.com` and all subdomains (`api.github.com`, etc.). Prefer parent domains over listing subdomains individually — e.g. `"anthropic.com"` instead of `"api.anthropic.com" "statsig.anthropic.com"`. Wildcard entries like `*.github.com` are also accepted (the `*.` prefix is stripped).
- Adding a new allowed domain is a config change in `.nixbox/config.nix`, not a firewall rule change.
