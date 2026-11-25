#!/bin/bash
set -e

echo 1 > /proc/sys/net/ipv4/ip_forward
ip link set lo up
ip addr add 10.0.0.100/32 dev lo 2>/dev/null || true
ip addr add 10.10.10.100/32 dev lo 2>/dev/null || true

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

setup_iface eth1 192.168.255.0/31
setup_iface eth2 192.168.255.2/31

#Tenant A
create_l2vni br-a10 vx-a10 10010
create_l2vni br-a20 vx-a20 10020

#Tenant B
create_l2vni br-b10 vx-b10 20010
create_l2vni br-b20 vx-b20 20020

echo "leaf l2evpn/vxlan setup completed"