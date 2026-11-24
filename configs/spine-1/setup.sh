#!/bin/bash
set -e

# IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Loopback (Router-ID)
ip link set lo up
ip addr add 10.0.0.1/32 dev lo 2>/dev/null || true

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

# Линки и /31-адреса (MTU 9000)
setup_iface eth1 192.168.255.1/31
setup_iface eth2 192.168.1.0/31
setup_iface eth3 192.168.1.2/31
setup_iface eth4 192.168.1.4/31
setup_iface eth5 192.168.1.6/31