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