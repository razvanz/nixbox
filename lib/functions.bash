#!/usr/bin/env bash
# Shared functions for nixbox CLI. Sourced by bin/nixbox and tests.
# This file must NOT call set -euo pipefail or define global state —
# that is the caller's responsibility.

# ---------------------------------------------------------------------------
# Logging & errors
# ---------------------------------------------------------------------------

die() { printf '\r%s\n' "ERROR: $*" >&2; exit 1; }
log() { printf '\r%s\n' "$*"; }
log_sub() { printf '\r    %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Process limits
# ---------------------------------------------------------------------------

# Raise the current shell's NOFILE soft+hard limit to $1 (default 524288).
# virtiofsd with --cache=auto accumulates backing-file FDs and pins hot-cache
# shares at the ceiling (#18). If the session's hard limit is below target
# (e.g. locked-down CI runners), sudo prlimit raises the kernel limit first
# so bash's ulimit can then set the soft limit. Children inherit both.
raise_nofile() {
    local target="${1:-524288}"
    if ulimit -n "$target" 2>/dev/null; then
        return 0
    fi
    log "==> Raising NOFILE hard limit to $target (requires sudo)..."
    sudo prlimit --pid $$ --nofile="$target:$target" \
        || die "Failed to raise NOFILE hard limit to $target"
    ulimit -n "$target" \
        || die "ulimit -n $target failed after raising hard limit"
}

# ---------------------------------------------------------------------------
# Network derivation (pure — depends only on slot + name)
# ---------------------------------------------------------------------------

# Sets: TAP_DEV TAP_HOST_IP TAP_GUEST_IP TAP_SUBNET TAP_CIDR TAP_MAC NFT_TABLE VSOCK_CID
# shellcheck disable=SC2034
derive_network() {
    local slot="$1" name="$2"
    local base=$((slot * 4))
    TAP_DEV="vm${slot}"
    TAP_HOST_IP="172.16.${base}.1"
    TAP_GUEST_IP="172.16.${base}.2"
    TAP_SUBNET="172.16.${base}.0/30"
    TAP_CIDR="172.16.${base}.1/30"
    TAP_MAC=$(printf '02:00:00:00:00:%02x' $((slot + 1)))
    NFT_TABLE="nixbox_${name}"
    VSOCK_CID=$((3 + slot))
}

# Returns real upstream DNS server IPs (one per line), excluding loopback/stub
# addresses. Reads /run/systemd/resolve/resolv.conf (real upstreams, not the
# systemd-resolved stub at 127.0.0.53) when available, falling back to
# /etc/resolv.conf. Falls back to 8.8.8.8 / 8.8.4.4 if no real servers found.
get_upstream_dns_servers() {
    local resolv_conf="${1:-}"
    if [ -z "$resolv_conf" ]; then
        resolv_conf="/run/systemd/resolve/resolv.conf"
        [ -f "$resolv_conf" ] || resolv_conf="/etc/resolv.conf"
    fi
    local servers=()
    while IFS= read -r line; do
        [[ "$line" =~ ^nameserver[[:space:]]+([^[:space:]]+) ]] || continue
        local ip="${BASH_REMATCH[1]}"
        [[ "$ip" =~ ^127\. ]] && continue
        [[ "$ip" == "::1" ]] && continue
        servers+=("$ip")
    done < "$resolv_conf"
    if [ ${#servers[@]} -eq 0 ]; then
        servers=("8.8.8.8" "8.8.4.4")
    fi
    printf '%s\n' "${servers[@]}"
}

# ---------------------------------------------------------------------------
# Slot management (filesystem-based, uses SLOTS_DIR / BYDIR_DIR)
# ---------------------------------------------------------------------------

allocate_slot() {
    local nixbox_dir="$1"
    mkdir -p "$SLOTS_DIR" "$BYDIR_DIR"
    local dir_hash
    dir_hash=$(echo -n "$nixbox_dir" | md5sum | cut -d' ' -f1)

    # Already have a slot?
    if [ -f "$BYDIR_DIR/$dir_hash" ]; then
        local existing_slot
        existing_slot=$(cat "$BYDIR_DIR/$dir_hash")
        if [ -f "$SLOTS_DIR/$existing_slot" ]; then
            echo "$existing_slot"; return 0
        fi
    fi

    # Find first available slot
    local slot
    for slot in $(seq 0 63); do
        if [ ! -f "$SLOTS_DIR/$slot" ]; then
            echo "$nixbox_dir" > "$SLOTS_DIR/$slot"
            echo "$slot" > "$BYDIR_DIR/$dir_hash"
            echo "$slot"; return 0
        fi
        # Stale check
        local slot_dir
        slot_dir=$(cat "$SLOTS_DIR/$slot")
        if [ ! -f "$slot_dir/state/pid" ] || ! kill -0 "$(cat "$slot_dir/state/pid")" 2>/dev/null; then
            local old_hash
            old_hash=$(echo -n "$slot_dir" | md5sum | cut -d' ' -f1)
            rm -f "$BYDIR_DIR/$old_hash"
            echo "$nixbox_dir" > "$SLOTS_DIR/$slot"
            echo "$slot" > "$BYDIR_DIR/$dir_hash"
            echo "$slot"; return 0
        fi
    done
    die "No available VM slots (max 64 concurrent VMs)"
}

release_slot() {
    local nixbox_dir="$1"
    local dir_hash
    dir_hash=$(echo -n "$nixbox_dir" | md5sum | cut -d' ' -f1)
    if [ -f "$BYDIR_DIR/$dir_hash" ]; then
        local slot
        slot=$(cat "$BYDIR_DIR/$dir_hash")
        rm -f "$SLOTS_DIR/$slot" "$BYDIR_DIR/$dir_hash"
    fi
}

get_slot() {
    local nixbox_dir="$1"
    local dir_hash
    dir_hash=$(echo -n "$nixbox_dir" | md5sum | cut -d' ' -f1)
    [ -f "$BYDIR_DIR/$dir_hash" ] && cat "$BYDIR_DIR/$dir_hash" || echo ""
}

# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

# shellcheck disable=SC2120
find_nixbox_dir() {
    local dir="${1:-$PWD}"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.nixbox/config.nix" ]; then
            echo "$dir/.nixbox"
            return
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

jq_field() { echo "$CONFIG_JSON" | jq -r "$1"; }

resolve_config() {
    local config_path
    config_path="$(realpath "$1")"
    CONFIG_JSON=$(nix eval --json --impure \
        --expr "(import ${NIXBOX_SRC}/lib/resolve.nix { configPath = ${config_path}; pluginsDir = ${NIXBOX_SRC}/plugins; })") \
        || die "Failed to evaluate config: $config_path"
}

get_project_name() {
    if [ -f "$NIXBOX_DIR/state/name" ]; then
        cat "$NIXBOX_DIR/state/name"
    else
        basename "$(dirname "$NIXBOX_DIR")"
    fi
}

run_hooks() {
    local event="$1"
    local hooks
    hooks=$(echo "$CONFIG_JSON" | jq -r ".hooks.\"$event\"[]" 2>/dev/null) || return 0
    [ -z "$hooks" ] && return 0
    log "==> Running $event hooks..."
    while IFS= read -r hook; do
        [ -z "$hook" ] && continue
        log_sub "hook: $hook"
        (cd "$(dirname "$NIXBOX_DIR")" && sh -c "$hook") || log_sub "WARNING: $event hook failed: $hook"
    done <<< "$hooks"
}

# ---------------------------------------------------------------------------
# Mount spec parsing
# ---------------------------------------------------------------------------

# Sets: MOUNT_SOURCE MOUNT_TARGET MOUNT_READONLY
# shellcheck disable=SC2034
parse_mount_spec() {
    MOUNT_SOURCE="" MOUNT_TARGET="" MOUNT_READONLY=""
    local spec="$1"
    [ -z "$spec" ] && return
    IFS=',' read -ra PARTS <<< "$spec"
    for part in "${PARTS[@]}"; do
        case "$part" in
            type=bind) ;;
            source=*) MOUNT_SOURCE="${part#source=}" ;;
            target=*) MOUNT_TARGET="${part#target=}" ;;
            readonly)  MOUNT_READONLY="1" ;;
            *) die "Unknown mount option: $part" ;;
        esac
    done
    MOUNT_SOURCE="${MOUNT_SOURCE/#\~/$HOME}"
    if [ -z "$MOUNT_SOURCE" ] || [ -z "$MOUNT_TARGET" ]; then
        die "Mount spec requires source and target"
    fi
    if [ ! -d "$MOUNT_SOURCE" ]; then
        die "Source directory does not exist: $MOUNT_SOURCE"
    fi
}

# ---------------------------------------------------------------------------
# nixbox dir initialization
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034
init_nixbox_dir() {
    if ! NIXBOX_DIR="$(find_nixbox_dir)"; then
        die "No .nixbox/ found (searched from $PWD to /). Run 'nixbox init' first."
    fi
    SSH_KEY="$NIXBOX_DIR/ssh/vm_key"
    SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")
}

# shellcheck disable=SC2034
init_nixbox_dir_or_active() {
    if NIXBOX_DIR="$(find_nixbox_dir 2>/dev/null)"; then
        :
    else
        local running=()
        mkdir -p "$SLOTS_DIR"
        for slot_file in "$SLOTS_DIR"/*; do
            [ -f "$slot_file" ] || continue
            local dir
            dir=$(cat "$slot_file")
            [ -f "$dir/state/pid" ] && kill -0 "$(cat "$dir/state/pid")" 2>/dev/null && running+=("$dir")
        done
        if [ ${#running[@]} -eq 1 ]; then
            NIXBOX_DIR="${running[0]}"
        elif [ ${#running[@]} -gt 1 ]; then
            echo "Multiple VMs running. Run from a project directory, or use 'nixbox status':" >&2
            for dir in "${running[@]}"; do
                local name
                name=$(cat "$dir/state/name" 2>/dev/null || basename "$(dirname "$dir")")
                echo "  - $name ($(dirname "$dir"))" >&2
            done
            exit 1
        else
            die "No .nixbox/ found and no active VM."
        fi
    fi
    SSH_KEY="$NIXBOX_DIR/ssh/vm_key"
    SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$SSH_KEY")

    # Derive network from persisted slot
    local vm_slot
    vm_slot=$(cat "$NIXBOX_DIR/state/slot" 2>/dev/null || echo "0")
    local name
    name=$(cat "$NIXBOX_DIR/state/name" 2>/dev/null || basename "$(dirname "$NIXBOX_DIR")")
    derive_network "$vm_slot" "$name"
}

# ---------------------------------------------------------------------------
# Build helpers
# ---------------------------------------------------------------------------

compute_build_hash() {
    local config_path="$1"
    local lock_file="$NIXBOX_DIR/flake.lock"
    (
        cat "$NIXBOX_SRC/flake.nix" \
            "$NIXBOX_SRC/lib/resolve.nix" \
            "$config_path" \
            "$NIXBOX_DIR/ssh/vm_key.pub"
        # Include user's pinned lock if present; its absence changes the hash
        if [ -f "$lock_file" ]; then
            cat "$lock_file"
        else
            echo "__no_lock__"
        fi
        find "$NIXBOX_SRC/plugins" -name '*.nix' -exec cat {} + 2>/dev/null || true
    ) | sha256sum | cut -d' ' -f1
}
