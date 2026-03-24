# 007: dnsmasq --user=root

**Date:** 2026-03-24
**Status:** accepted

## Problem

dnsmasq defaults to dropping privileges to the `nobody` user after binding its listen socket. However, the pidfile is written to a user-owned state directory (`.nixbox/state/`). The `nobody` user cannot write there, causing dnsmasq to hang or fail at startup.

This looks like a security configuration that should be "fixed" by removing `--user=root`. **Don't.**

## Decision

Run dnsmasq with implicit root privileges (no `--user=` override to drop privileges). dnsmasq is already started via `sudo` and only listens on the TAP interface (`172.16.0.1`), not on external interfaces or localhost.

The TAP interface is only reachable from the local VM — the attack surface is limited to a process the user explicitly started.

## Consequences

- dnsmasq starts without interaction or permission errors.
- No privilege escalation risk: dnsmasq's listen address is restricted to the TAP interface, which only the VM can reach.
- If the pidfile location moves to a root-owned directory (e.g., `/run/nixbox/`), privilege dropping could be reconsidered.
