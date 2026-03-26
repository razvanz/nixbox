#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Allow overriding bats binary (CI installs it separately)
BATS="${BATS:-bats}"

exec "$BATS" "$SCRIPT_DIR/unit/"
