# 010: Sharing Claude OAuth session with the guest

**Date:** 2026-03-24
**Status:** accepted

## Problem

To run Claude Code inside the guest VM, the guest needs an authenticated Anthropic session. Requiring users to `claude /login` inside the VM every session is friction-heavy (copy-paste URL to host browser, complete OAuth flow).

Claude Code stores state across three locations:

- **`~/.config/Claude/`** — OAuth token (in `config.json` → `oauth:tokenCache`), UI preferences
- **`~/.claude/`** — project memories, settings, CLAUDE.md, debug logs, telemetry, todos, backups
- **`~/.claude.json`** — client state (theme, onboarding flags, usage stats)

## Decision

Share both directories via **virtiofs mounts** in the project config:

```nix
mounts = [
  { source = "~/.claude";        target = "~/.claude"; }
  { source = "~/.config/Claude"; target = "~/.config/Claude"; }
];
```

This works because virtiofs provides transparent filesystem passthrough — the guest reads the host's OAuth token in-place via the FUSE layer. No copy or re-auth needed.

**`~/.claude.json`** is not on a virtiofs mount (it lives in `$HOME`, which is the guest's local root disk). Claude Code requires it at startup. The plugin provides a command to sync it from the host:

```bash
nixbox claude-code sync-config   # SCPs ~/.claude.json from host into VM
```

This can be automated via a lifecycle hook (`hooks.post-up`) so it runs on every `nixbox up`.

### What didn't work

- **Copying `~/.config/Claude/config.json`** — Claude Code reported "Not logged in" when the token file was copied rather than accessed in-place. The OAuth flow likely validates something about the file's origin. Virtiofs passthrough avoids this.

## Consequences

- **No login required** — the guest reuses the host's authenticated session via virtiofs passthrough.
- **Bidirectional writes** — the guest writes to the host's `~/.claude/` and `~/.config/Claude/`. Settings and project memories persist across VM sessions.
- **tmpfs overlays needed** — `~/.claude/{debug,statsig,telemetry,todos}` are write-heavy paths where Node.js uses `O_TMPFILE`, which virtiofs doesn't support (see ADR 001). Users must apply tmpfs overlays in their setup scripts.
- **Host and guest share a single session** — concurrent Claude Code on both sides could conflict. In practice the VM is the primary workspace.
- **Security tradeoff** — a compromised sandbox has the developer's Anthropic session. Acceptable for personal use.
