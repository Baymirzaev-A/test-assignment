#!/bin/bash

set -e

# IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Loopback (Router-ID)
ip link set lo up
ip addr add 10.0.1.1/32 dev lo

# Линки и /31-адреса (MTU 9000)
# eth1 -> Spine-1 (192.168.1.0/31)
ip link set eth1 up mtu 9000
ip addr add 192.168.1.1/31 dev eth1

# eth2 -> Spine-2 (192.168.2.0/31)
ip link set eth2 up mtu 9000
ip addr add 192.168.2.1/31 dev eth2

# eth3 -> Leaf-2 (MLAG peer-link, L2, no IP)
ip link set eth3 up mtu 9000