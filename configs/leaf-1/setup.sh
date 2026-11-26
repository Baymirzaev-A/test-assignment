#!/bin/bash
set -e

VTEP_IP="10.10.10.1"

echo "=== Leaf-1 setup ==="

# Loopbacks: Router-ID и VTEP
ip link set lo up
ip addr replace 10.0.1.1/32 dev lo
ip addr replace 10.10.10.1/32 dev lo

# Underlay
setup_iface() {
    local iface="$1"
    local addr="$2"

    if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" mtu 9000 up
        ip addr replace "$addr" dev "$iface"
    fi
}

setup_iface eth1 192.168.1.1/31
setup_iface eth2 192.168.2.1/31

# MLAG peer-link
ip link set eth3 mtu 9000 up

# Create L2 VNI
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

# Tenant A
create_l2vni br-a10 vx-a10 10010
create_l2vni br-a20 vx-a20 10020

# Tenant B
create_l2vni br-b10 vx-b10 20010
create_l2vni br-b20 vx-b20 20020

# Connect tagged server VLANs to their tenant bridges
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

# srv-mh-01: Tenant A
# EVPN MH - srv-mh-01
ES_BOND="bond-mh01"
ES_ID="1001"
ES_MAC="02:00:00:00:10:01"
ES_DF_PREF="200"

ip link add "$ES_BOND" type bond mode 802.3ad 2>/dev/null || true
ip link set "$ES_BOND" type bond mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer2+3
ip link set "$ES_BOND" mtu 9000

ip link set eth4 down
ip link set eth4 nomaster 2>/dev/null || true
ip link set eth4 master "$ES_BOND"
ip link set eth4 up
ip link set "$ES_BOND" up

attach_vlan "$ES_BOND" 10 br-a10
attach_vlan "$ES_BOND" 20 br-a20

vtysh \
    -c "configure terminal" \
    -c "interface ${ES_BOND}" \
    -c "evpn mh es-id ${ES_ID}" \
    -c "evpn mh es-sys-mac ${ES_MAC}" \
    -c "evpn mh es-df-pref ${ES_DF_PREF}" \
    -c "end" \
    -c "write memory"

ip link set dev bond-mh01 down
ip link set dev bond-mh01 type bond \
    ad_actor_system 02:00:00:00:10:01
ip link set dev bond-mh01 up

# srv-mlag-01: Tenant A
attach_vlan eth5 10 br-a10
attach_vlan eth5 20 br-a20

# srv-mlag-02: Tenant B
attach_vlan eth6 10 br-b10
attach_vlan eth6 20 br-b20

echo "=== Leaf-1 setup completed ==="