#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_dirs
}

teardown() {
    teardown_temp_dirs
}

@test "allocate_slot assigns slot 0 for first project" {
    local slot
    slot=$(allocate_slot "/tmp/fake-project/.nixbox")
    [ "$slot" = "0" ]
    [ -f "$SLOTS_DIR/0" ]
}

@test "allocate_slot returns same slot for same dir" {
    local slot1 slot2
    slot1=$(allocate_slot "/tmp/proj-a/.nixbox")
    slot2=$(allocate_slot "/tmp/proj-a/.nixbox")
    [ "$slot1" = "$slot2" ]
}

@test "allocate_slot assigns different slots for different dirs" {
    # Simulate slot 0 held by a live process (use our own PID)
    local dir_a="$TEST_TMPDIR/proj-a/.nixbox"
    mkdir -p "$dir_a/state"
    echo "$$" > "$dir_a/state/pid"

    local slot1
    slot1=$(allocate_slot "$dir_a")
    [ "$slot1" = "0" ]

    local slot2
    slot2=$(allocate_slot "/tmp/proj-b/.nixbox")
    [ "$slot2" = "1" ]
}

@test "release_slot frees the slot" {
    local slot
    slot=$(allocate_slot "/tmp/proj/.nixbox")
    [ -f "$SLOTS_DIR/$slot" ]

    release_slot "/tmp/proj/.nixbox"
    [ ! -f "$SLOTS_DIR/$slot" ]
}

@test "get_slot returns allocated slot" {
    local slot
    slot=$(allocate_slot "/tmp/proj/.nixbox")
    local got
    got=$(get_slot "/tmp/proj/.nixbox")
    [ "$got" = "$slot" ]
}

@test "get_slot returns empty for unknown dir" {
    local got
    got=$(get_slot "/tmp/unknown/.nixbox")
    [ "$got" = "" ]
}

@test "allocate_slot reclaims stale slots" {
    # Fill slot 0 with a dir whose PID file points to a dead process
    local stale_dir="$TEST_TMPDIR/stale-project/.nixbox"
    mkdir -p "$stale_dir/state"
    echo "99999999" > "$stale_dir/state/pid"
    echo "$stale_dir" > "$SLOTS_DIR/0"
    local stale_hash
    stale_hash=$(echo -n "$stale_dir" | md5sum | cut -d' ' -f1)
    echo "0" > "$BYDIR_DIR/$stale_hash"

    # New project should reclaim slot 0
    local slot
    slot=$(allocate_slot "/tmp/new-proj/.nixbox")
    [ "$slot" = "0" ]
}
