#!/bin/bash
set -e

# IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Loopback (Router-ID)
ip link set lo up
ip addr add 10.0.1.1/32 dev lo 2>/dev/null || true

# поднять интерфейс, если он существует (для теста)
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

# eth1 -> Spine-1 (192.168.1.0/31)
setup_iface eth1 192.168.1.1/31

# eth2 -> Spine-2 (192.168.2.0/31)
setup_iface eth2 192.168.2.1/31

# eth3 -> Leaf-2 (MLAG peer-link, L2, no IP)
if ip link show eth3 >/dev/null 2>&1; then
    ip link set eth3 up mtu 9000
fi