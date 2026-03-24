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
