# 005: Docker FORWARD chain breaks VM networking

**Date:** 2026-03-24
**Status:** accepted

## Problem

On hosts running Docker, the iptables FORWARD chain has `policy DROP`. The kernel evaluates iptables **before** nftables on the FORWARD hook. This means even correct nftables ACCEPT rules for the TAP interface (`vmtap0`) are never reached — Docker's iptables drops the packets first.

The failure mode is deceptive: `nft list ruleset` shows correct rules, `iptables -L FORWARD` shows the DROP policy, but the connection between them isn't obvious. VM networking silently fails with no error messages.

## Decision

Before applying nftables rules, check if the `DOCKER-USER` iptables chain exists. If it does, insert ACCEPT rules into it for the TAP interface:

```bash
sudo iptables -I DOCKER-USER -i vmtap0 -j ACCEPT
sudo iptables -I DOCKER-USER -o vmtap0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

Cleanup (`nixbox down`) removes both nftables rules AND the iptables DOCKER-USER rules.

This applies to both `filtered` and `open` network modes. The `off` mode doesn't forward packets, so it's not affected.

## Consequences

- VM networking works on Docker hosts without additional user configuration.
- Two firewall systems must be maintained: nftables for our rules, iptables for Docker compatibility.
- If Docker is not installed, the `iptables -L DOCKER-USER` check fails silently and the rules are skipped.
- If Docker is installed after VM boot, networking will break until `nixbox down && nixbox up`.
