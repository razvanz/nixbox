#!/usr/bin/env bash
# Minimal E2E test: init → build → boot → SSH → teardown.
# Requires KVM, sudo, and all nixbox runtime dependencies.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d)"

# Build the Nix-packaged CLI (includes all wrapped deps: virtiofsd, jq, etc.)
echo "==> Building nixbox CLI..."
NIXBOX_CLI="$(nix build "$PROJECT_ROOT#nixbox" --no-link --print-out-paths)/bin/nixbox"

cleanup() {
    echo "==> Cleanup..."
    "$NIXBOX_CLI" down 2>/dev/null || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "==> Creating test project in $TEST_DIR"
cd "$TEST_DIR"
"$NIXBOX_CLI" init

# Overwrite template config with minimal test config
rm -f .nixbox/config.nix
cat > .nixbox/config.nix <<'NIX'
{
  name = "e2e-test";
  network.mode = "open";
}
NIX

echo "==> Building VM runner..."
"$NIXBOX_CLI" build

echo "==> Starting VM..."
"$NIXBOX_CLI" up

echo "==> Testing SSH command execution..."
output=$("$NIXBOX_CLI" run "echo hello-from-vm")
if [ "$output" = "hello-from-vm" ]; then
    echo "  ok: command execution"
else
    echo "  FAIL: expected 'hello-from-vm', got '$output'"
    exit 1
fi

echo "==> Testing network connectivity from VM..."
"$NIXBOX_CLI" run "curl -sf --max-time 10 https://cache.nixos.org >/dev/null"
echo "  ok: network connectivity"

echo "==> Shutting down VM..."
"$NIXBOX_CLI" down

echo ""
echo "E2E: all checks passed"
