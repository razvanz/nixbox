#!/usr/bin/env bash
set -euo pipefail

# virtiofs doesn't support O_TMPFILE — overlay tmpfs on write-heavy Claude dirs
for d in debug statsig telemetry todos; do
  sudo mkdir -p ~/.claude/$d
  sudo mount -t tmpfs tmpfs ~/.claude/$d
  sudo chown "$(whoami):users" ~/.claude/$d
done
