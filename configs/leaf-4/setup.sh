#!/bin/bash
set -e

echo 1 > /proc/sys/net/ipv4/ip_forward
ip link set lo up
ip addr add 10.0.1.4/32 dev lo 2>/dev/null || true
ip addr add 10.10.10.4/32 dev lo 2>/dev/null || true

setup_iface() {
    local iface=$1
    local ip=$2
    if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" up mtu 9000
        ip addr add "$ip" dev "$iface" 2>/dev/null || true
    else
        echo "Interface $iface not found, skipping"
    fi
}

setup_iface eth1 192.168.1.7/31
setup_iface eth2 192.168.2.7/31

if ip link show eth3 >/dev/null 2>&1; then
    ip link set eth3 up mtu 9000
fi

#Tenant A
create_l2vni br-a10 vx-a10 10010
create_l2vni br-a20 vx-a20 10020

#Tenant B
create_l2vni br-b10 vx-b10 20010
create_l2vni br-b20 vx-b20 20020

echo "leaf l2evpn/vxlan setup completed"

echo "Configuring server-facing interfaces on Leaf-4"

attach_vlan() {
    local parent="$1"
    local vlan="$2"
    local bridge="$3"
    local subif="${parent}.${vlan}"

    ip link set "$parent" mtu 9000 up

    if ! ip link show "$subif" >/dev/null 2>&1; then
        ip link add link "$parent" name "$subif" type vlan id "$vlan"
    fi

    ip link set "$subif" mtu 8950 up
    ip link set "$subif" master "$bridge"
}

# EVPN Multihoming: srv-mh-02, Tenant B
attach_vlan eth4 10 br-b10
attach_vlan eth4 20 br-b20

# MLAG: srv-mlag-03, Tenant A
attach_vlan eth5 10 br-a10
attach_vlan eth5 20 br-a20

# MLAG: srv-mlag-04, Tenant B
attach_vlan eth6 10 br-b10
attach_vlan eth6 20 br-b20

echo "Leaf-4 server interfaces configured"