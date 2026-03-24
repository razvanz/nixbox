#!/usr/bin/env bash
set -euo pipefail

# Plugin command: nixbox claude-code sync-config
# SCP the host's ~/.claude.json into the VM.

die() { printf '\r%s\n' "ERROR: $*" >&2; exit 1; }
log() { printf '\r%s\n' "$*"; }
log_sub() { printf '\r    %s\n' "$*"; }

src="$HOME/.claude.json"
[ -f "$src" ] || die "No ~/.claude.json found on host"

log "==> Syncing Claude config to VM..."
nixbox run "cat > ~/.claude.json" < "$src"
log_sub "Synced ~/.claude.json"
