#!/bin/bash

set -e

# IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Loopback (Router-ID)
ip link set lo up
ip addr add 10.0.0.1/32 dev lo

# Линки и /31-адреса (MTU 9000)
# eth1 -> Gateway (192.168.255.0/31)
ip link set eth1 up mtu 9000
ip addr add 192.168.255.1/31 dev eth1

# eth2 -> Leaf-1 (192.168.1.0/31)
ip link set eth2 up mtu 9000
ip addr add 192.168.1.0/31 dev eth2

# eth3 -> Leaf-2 (192.168.1.2/31)
ip link set eth3 up mtu 9000
ip addr add 192.168.1.2/31 dev eth3

# eth4 -> Leaf-3 (192.168.1.4/31)
ip link set eth4 up mtu 9000
ip addr add 192.168.1.4/31 dev eth4

# eth5 -> Leaf-4 (192.168.1.6/31)
ip link set eth5 up mtu 9000
ip addr add 192.168.1.6/31 dev eth5