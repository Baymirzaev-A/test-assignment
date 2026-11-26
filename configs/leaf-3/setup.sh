#!/bin/bash
set -e

VTEP_IP="10.10.10.3"

echo "=== Leaf-3 setup ==="

ip link set lo up
ip addr replace 10.0.1.3/32 dev lo
ip addr replace 10.10.10.3/32 dev lo

setup_iface() {
    local iface="$1"
    local addr="$2"

    if ip link show "$iface" >/dev/null 2>&1; then
        ip link set "$iface" mtu 9000 up
        ip addr replace "$addr" dev "$iface"
    fi
}

setup_iface eth1 192.168.1.5/31
setup_iface eth2 192.168.2.5/31

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

# ===== EVPN MH + VLAN-aware tenant bridges =====
ES_BOND="bond-mh02"
ES_ID="1002"
ES_MAC="02:00:00:00:10:02"
ES_DF_PREF="200"

BR_A="br-a"
BR_B="br-b"
VX_A="vx-a"
VX_B="vx-b"
VTEP_IP="10.10.10.3"

ip link add "$BR_A" type bridge vlan_filtering 1 vlan_default_pvid 0 2>/dev/null || true
ip link add "$BR_B" type bridge vlan_filtering 1 vlan_default_pvid 0 2>/dev/null || true
ip link set "$BR_A" mtu 8950 up
ip link set "$BR_B" mtu 8950 up

ip link add "$VX_A" type vxlan local "$VTEP_IP" dstport 4789 nolearning external vnifilter 2>/dev/null || true
ip link add "$VX_B" type vxlan local "$VTEP_IP" dstport 4789 nolearning external vnifilter 2>/dev/null || true
ip link set "$VX_A" mtu 8950
ip link set "$VX_B" mtu 8950
ip link set "$VX_A" master "$BR_A"
ip link set "$VX_B" master "$BR_B"
ip link set "$VX_A" type bridge_slave learning off
ip link set "$VX_B" type bridge_slave learning off
bridge link set dev "$VX_A" vlan_tunnel on
bridge link set dev "$VX_B" vlan_tunnel on
ip link set "$VX_A" up
ip link set "$VX_B" up

for vid in 10 20; do
    bridge vlan add dev "$BR_A" vid "$vid" self 2>/dev/null || true
    bridge vlan add dev "$VX_A" vid "$vid" 2>/dev/null || true
done
bridge vni add dev "$VX_A" vni 10010 2>/dev/null || true
bridge vni add dev "$VX_A" vni 10020 2>/dev/null || true
bridge vlan add dev "$VX_A" vid 10 tunnel_info id 10010 2>/dev/null || true
bridge vlan add dev "$VX_A" vid 20 tunnel_info id 10020 2>/dev/null || true

for vid in 10 20; do
    bridge vlan add dev "$BR_B" vid "$vid" self 2>/dev/null || true
    bridge vlan add dev "$VX_B" vid "$vid" 2>/dev/null || true
done
bridge vni add dev "$VX_B" vni 20010 2>/dev/null || true
bridge vni add dev "$VX_B" vni 20020 2>/dev/null || true
bridge vlan add dev "$VX_B" vid 10 tunnel_info id 20010 2>/dev/null || true
bridge vlan add dev "$VX_B" vid 20 tunnel_info id 20020 2>/dev/null || true

# EVPN MH bond: Tenant B
ip link set eth4 down
ip link set eth4 nomaster 2>/dev/null || true
ip link add "$ES_BOND" type bond mode 802.3ad 2>/dev/null || true
ip link set "$ES_BOND" down
ip link set "$ES_BOND" type bond mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer2+3 ad_actor_system "$ES_MAC"
ip link set "$ES_BOND" mtu 9000
ip link set eth4 master "$ES_BOND"
ip link set eth4 up
ip link set "$ES_BOND" up
ip link set "$ES_BOND" master "$BR_B"
bridge vlan add dev "$ES_BOND" vid 10
bridge vlan add dev "$ES_BOND" vid 20

# MLAG server ports
ip link set eth5 down
ip link set eth5 nomaster 2>/dev/null || true
ip link set eth5 mtu 9000 up
ip link set eth5 master "$BR_A"
bridge vlan add dev eth5 vid 10
bridge vlan add dev eth5 vid 20

ip link set eth6 down
ip link set eth6 nomaster 2>/dev/null || true
ip link set eth6 mtu 9000 up
ip link set eth6 master "$BR_B"
bridge vlan add dev eth6 vid 10
bridge vlan add dev eth6 vid 20

vtysh -c "configure terminal" \
  -c "interface ${ES_BOND}" \
  -c "evpn mh es-id ${ES_ID}" \
  -c "evpn mh es-sys-mac ${ES_MAC}" \
  -c "evpn mh es-df-pref ${ES_DF_PREF}" \
  -c "end" \
  -c "write memory"

ip link set dev bond-mh02 down
ip link set dev bond-mh02 type bond \
    ad_actor_system 02:00:00:00:10:02
ip link set dev bond-mh02 up

# srv-mlag-03: Tenant A
attach_vlan eth5 10 br-a10
attach_vlan eth5 20 br-a20

# srv-mlag-04: Tenant B
attach_vlan eth6 10 br-b10
attach_vlan eth6 20 br-b20

echo "=== Leaf-3 setup completed ==="