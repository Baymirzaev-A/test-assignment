#!/bin/bash
set -euo pipefail

echo "=== Gateway VTEP setup ==="

# Enable IPv4 forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Loopbacks: underlay router-id and overlay VTEP
ip link set lo up
ip addr replace 10.0.0.100/32 dev lo
ip addr replace 10.10.10.100/32 dev lo

# Underlay interfaces
setup_iface() {
    local iface="$1"
    local addr="$2"

    if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" mtu 9000 up
        ip addr replace "$addr" dev "$iface"
    else
        echo "WARNING: $iface not found"
    fi
}

setup_iface eth1 192.168.255.0/31
setup_iface eth2 192.168.255.2/31

# Create an L2 bridge and VXLAN VTEP for a tenant VLAN/VNI
create_l2vni() {
    local bridge="$1"
    local vxlan="$2"
    local vni="$3"

    # Create bridge if it does not exist
    if ! ip link show "$bridge" >/dev/null 2>&1; then
        ip link add name "$bridge" type bridge
    fi

    # Create VXLAN interface if it does not exist
    if ! ip link show "$vxlan" >/dev/null 2>&1; then
        ip link add name "$vxlan" type vxlan \
            id "$vni" \
            local 10.10.10.100 \
            dstport 4789 \
            nolearning
    fi

    ip link set "$bridge" mtu 9000 up
    ip link set "$vxlan" mtu 9000 up
    ip link set "$vxlan" master "$bridge"
}

# Tenant A
create_l2vni br-a10 vx-a10 10010
create_l2vni br-a20 vx-a20 10020

# Tenant B
create_l2vni br-b10 vx-b10 20010
create_l2vni br-b20 vx-b20 20020

echo "=== Gateway VTEP setup completed ==="