#!/bin/bash
set -e

VTEP_IP="10.10.10.4"

echo "=== Leaf-4 setup ==="

ip link set lo up
ip addr replace 10.0.1.4/32 dev lo
ip addr replace 10.10.10.4/32 dev lo

setup_iface() {
    local iface="$1"
    local addr="$2"

    if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" mtu 9000 up
        ip addr replace "$addr" dev "$iface"
    fi
}

setup_iface eth1 192.168.1.7/31
setup_iface eth2 192.168.2.7/31

ip link set eth3 mtu 9000 up

create_l2vni() {
    local bridge="$1"
    local vxlan="$2"
    local vni="$3"

    ip link add "$bridge" type bridge 2>/dev/null || true
    ip link add "$vxlan" type vxlan \
        id "$vni" \
        local "$VTEP_IP" \
        dstport 4789 \
        nolearning 2>/dev/null || true

    ip link set "$bridge" mtu 8950 up
    ip link set "$vxlan" mtu 8950
    ip link set "$vxlan" master "$bridge"
    ip link set "$vxlan" type bridge_slave learning off
    ip link set "$vxlan" up
}

create_l2vni br-a10 vx-a10 10010
create_l2vni br-a20 vx-a20 10020
create_l2vni br-b10 vx-b10 20010
create_l2vni br-b20 vx-b20 20020

attach_vlan() {
    local parent="$1"
    local vlan="$2"
    local bridge="$3"
    local subif="${parent}.${vlan}"

    ip link set "$parent" mtu 9000 up

    ip link add link "$parent" name "$subif" type vlan id "$vlan" \
        2>/dev/null || true

    ip link set "$subif" mtu 8950 up
    ip link set "$subif" master "$bridge"
}

# srv-mh-02: Tenant B
attach_vlan eth4 10 br-b10
attach_vlan eth4 20 br-b20

# srv-mlag-03: Tenant A
attach_vlan eth5 10 br-a10
attach_vlan eth5 20 br-a20

# srv-mlag-04: Tenant B
attach_vlan eth6 10 br-b10
attach_vlan eth6 20 br-b20

echo "=== Leaf-4 setup completed ==="