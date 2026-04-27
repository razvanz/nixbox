#!/usr/bin/env bash
set -euo pipefail

# SBT credentials for private Maven/Nexus — activated by env vars
if [ -n "${MAVEN_REPO_HOST:-}" ] && [ -n "${MAVEN_REPO_USER:-}" ] && [ -n "${MAVEN_REPO_PASSWORD:-}" ]; then
  mkdir -p ~/.sbt
  cat > ~/.sbt/.credentials <<EOF
realm=Sonatype Nexus Repository Manager
host=$MAVEN_REPO_HOST
user=$MAVEN_REPO_USER
password=$MAVEN_REPO_PASSWORD
EOF
fi

# One-shot warmup of host caches into root.img on first boot per workspace.
# Runtime sbt I/O lives entirely on root.img (see ADR-015).
warm_cache() {
  local src="$1" dst="$2" name="$3"
  [ -d "$src" ] || return 0
  [ -f "$dst/.nixbox-warmed" ] && return 0
  echo "==> Warming $name cache from host (one-time per workspace)..."
  mkdir -p "$dst"
  rsync -a "$src/" "$dst/"
  touch "$dst/.nixbox-warmed"
}

warm_cache /mnt/host-cache/coursier "$HOME/.cache/coursier" coursier
warm_cache /mnt/host-cache/ivy2 "$HOME/.ivy2" ivy2
