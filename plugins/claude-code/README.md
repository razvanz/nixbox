# claude-code

Runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside the VM.

## Usage

```nix
{ plugins = [ "claude-code" ]; }
```

## What it provides

| Category | Details |
|---|---|
| **Packages** | `claude-code` |
| **Mounts** | `~/.claude` — preserves config, credentials, and session history across VM restarts |
| **Domains** | `anthropic.com`, `claude.com`, `sentry.io` |
| **Setup** | Overlays tmpfs on `~/.claude/{debug,statsig,telemetry,todos}` to work around virtiofs lacking `O_TMPFILE` support |

## Commands

```bash
nixbox claude-code sync-config   # SCP host's ~/.claude.json into the VM
```
