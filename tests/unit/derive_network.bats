#!/usr/bin/env bats

load test_helper

@test "derive_network slot 0 produces correct IPs" {
    derive_network 0 "test-project"
    [ "$TAP_DEV" = "vm0" ]
    [ "$TAP_HOST_IP" = "172.16.0.1" ]
    [ "$TAP_GUEST_IP" = "172.16.0.2" ]
    [ "$TAP_SUBNET" = "172.16.0.0/30" ]
    [ "$TAP_CIDR" = "172.16.0.1/30" ]
    [ "$VSOCK_CID" = "3" ]
}

@test "derive_network slot 1 offsets by 4" {
    derive_network 1 "project"
    [ "$TAP_DEV" = "vm1" ]
    [ "$TAP_HOST_IP" = "172.16.4.1" ]
    [ "$TAP_GUEST_IP" = "172.16.4.2" ]
    [ "$TAP_SUBNET" = "172.16.4.0/30" ]
    [ "$VSOCK_CID" = "4" ]
}

@test "derive_network slot 63 (max) produces valid addresses" {
    derive_network 63 "max"
    [ "$TAP_DEV" = "vm63" ]
    # 63 * 4 = 252
    [ "$TAP_HOST_IP" = "172.16.252.1" ]
    [ "$TAP_GUEST_IP" = "172.16.252.2" ]
    [ "$TAP_SUBNET" = "172.16.252.0/30" ]
    [ "$VSOCK_CID" = "66" ]
}

@test "derive_network MAC address increments with slot" {
    derive_network 0 "a"
    [ "$TAP_MAC" = "02:00:00:00:00:01" ]

    derive_network 15 "b"
    [ "$TAP_MAC" = "02:00:00:00:00:10" ]

    derive_network 63 "c"
    [ "$TAP_MAC" = "02:00:00:00:00:40" ]
}

@test "derive_network NFT_TABLE includes project name" {
    derive_network 5 "my-project"
    [ "$NFT_TABLE" = "nixbox_my-project" ]
}
