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

dump_debug() {
    echo "==> DEBUG: pre-cleanup diagnosis:"
    cat .nixbox/run/ssh-fail-diag.log 2>/dev/null || echo "(no ssh-fail-diag.log)"
    echo "==> DEBUG: vm.log (full):"
    cat .nixbox/run/vm.log 2>/dev/null || echo "(no vm.log)"
    echo "==> DEBUG: dnsmasq log:"
    cat .nixbox/run/dnsmasq.log 2>/dev/null || echo "(no dnsmasq.log)"
    echo "==> DEBUG: SSH wait errors (last 5 lines):"
    tail -5 .nixbox/run/ssh-wait.log 2>/dev/null || echo "(no ssh-wait.log)"
}

cleanup() {
    echo "==> Cleanup..."
    "$NIXBOX_CLI" down 2>/dev/null || true
    chmod -R u+w "$TEST_DIR" 2>/dev/null || true
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
"$NIXBOX_CLI" up || { dump_debug; exit 1; }

echo "==> Verifying virtiofsd FD limits..."
for pidfile in .nixbox/state/virtiofsd_*_pid; do
    [ -f "$pidfile" ] || continue
    pid=$(cat "$pidfile")
    tag=$(basename "$pidfile" | sed 's/virtiofsd_//;s/_pid//')
    max_fds=$(awk '/^Max open files/{print $4}' "/proc/$pid/limits")
    if [ "$max_fds" -ge 524288 ]; then
        echo "  ok: virtiofsd ($tag) has $max_fds max FDs"
    else
        echo "  FAIL: virtiofsd ($tag) has $max_fds max FDs, expected >= 524288"
        exit 1
    fi
done

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
