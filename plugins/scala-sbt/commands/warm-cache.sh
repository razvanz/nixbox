#!/usr/bin/env bash
set -euo pipefail

# Plugin command: nixbox scala-sbt warm-cache
# One-shot copy of the host's coursier and ivy2 caches into the guest's
# ~/.cache/coursier and ~/.ivy2. Idempotent — guarded by a sentinel file
# inside each guest cache dir. Invoked from the plugin's post-up hook so
# warmup runs automatically once per workspace.

die() { printf '\r%s\n' "ERROR: $*" >&2; exit 1; }
log() { printf '\r%s\n' "$*"; }
log_sub() { printf '\r    %s\n' "$*"; }

warm() {
    local host_src="$1" guest_relpath="$2" name="$3"
    [ -d "$host_src" ] || { log_sub "skip $name: $host_src not found on host"; return 0; }

    if nixbox run "test -f \"\$HOME/$guest_relpath/.nixbox-warmed\"" 2>/dev/null; then
        log_sub "$name: already warmed"
        return 0
    fi

    log "==> Warming $name cache from host (one-time per workspace)..."
    nixbox run "mkdir -p \"\$HOME/$guest_relpath\""
    tar -C "$host_src" -cf - . \
        | nixbox run "tar -C \"\$HOME/$guest_relpath\" -xf - && touch \"\$HOME/$guest_relpath/.nixbox-warmed\""
    log_sub "$name: done"
}

warm "$HOME/.cache/coursier" ".cache/coursier" coursier
warm "$HOME/.ivy2"           ".ivy2"           ivy2
