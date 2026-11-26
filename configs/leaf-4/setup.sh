#!/bin/bash
set -euo pipefail

LEAF="Leaf-4"
VTEP_IP="10.10.10.4"

ES_BOND="bond-mh02"
ES_ID="1002"
ES_MAC="02:00:00:00:10:02"
ES_DF_PREF="100"
ES_BRIDGE="br-b"

echo "=== ${LEAF} setup ==="

# Loopbacks
ip link set lo up
ip addr replace 10.0.1.4/32 dev lo
ip addr replace "${VTEP_IP}/32" dev lo

# Underlay
setup_iface() {
    local iface="$1"
    local addr="$2"

    ip link set "$iface" mtu 9000 up
    ip addr replace "$addr" dev "$iface"
}

setup_iface eth1 192.168.1.7/31
setup_iface eth2 192.168.2.7/31

# eth3 is reserved for future MLAG peer-link.
ip link set eth3 mtu 9000 up

# Remove old L2VNI layout and stale VLAN subinterfaces.
for iface in vx-a10 vx-a20 vx-b10 vx-b20 \
             eth5.10 eth5.20 eth6.10 eth6.20 \
             bond-mh02.10 bond-mh02.20; do
    ip link del "$iface" 2>/dev/null || true
done

ip link del bond-mh02 2>/dev/null || true

for bridge in br-a10 br-a20 br-b10 br-b20; do
    ip link del "$bridge" 2>/dev/null || true
done

# Create tenant VLAN-aware bridges.
ip link add br-a type bridge vlan_filtering 1 vlan_default_pvid 0
ip link add br-b type bridge vlan_filtering 1 vlan_default_pvid 0

ip link set br-a mtu 8950 up
ip link set br-b mtu 8950 up

create_vxlan() {
    local bridge="$1"
    local vxlan="$2"
    local vni10="$3"
    local vni20="$4"

    ip link add "$vxlan" type vxlan \
        local "$VTEP_IP" \
        dstport 4789 \
        nolearning \
        external \
        vnifilter

    ip link set "$vxlan" mtu 8950
    ip link set "$vxlan" master "$bridge"
    ip link set "$vxlan" type bridge_slave learning off
    bridge link set dev "$vxlan" vlan_tunnel on

    bridge vlan add dev "$bridge" vid 10 self
    bridge vlan add dev "$bridge" vid 20 self

    bridge vni add dev "$vxlan" vni "$vni10"
    bridge vni add dev "$vxlan" vni "$vni20"

    bridge vlan add dev "$vxlan" vid 10 tunnel_info id "$vni10"
    bridge vlan add dev "$vxlan" vid 20 tunnel_info id "$vni20"

    ip link set "$vxlan" up
}

create_vxlan br-a vx-a 10010 10020
create_vxlan br-b vx-b 20010 20020

# Server trunk ports.
setup_trunk() {
    local iface="$1"
    local bridge="$2"

    ip link set "$iface" down
    ip link set "$iface" mtu 9000
    ip link set "$iface" master "$bridge"

    bridge vlan add dev "$iface" vid 10
    bridge vlan add dev "$iface" vid 20

    ip link set "$iface" up
}

setup_trunk eth5 br-a
setup_trunk eth6 br-b

# EVPN Multihoming: srv-mh-02 on eth4.
ip link add "$ES_BOND" type bond mode 802.3ad 2>/dev/null || true

ip link set "$ES_BOND" down
ip link set "$ES_BOND" type bond \
    mode 802.3ad \
    miimon 100 \
    lacp_rate fast \
    xmit_hash_policy layer2+3 \
    ad_actor_system "$ES_MAC"

ip link set "$ES_BOND" mtu 9000

ip link set eth4 down
ip link set eth4 nomaster 2>/dev/null || true
ip link set eth4 mtu 9000
ip link set eth4 master "$ES_BOND"
ip link set eth4 up
ip link set "$ES_BOND" up

ip link set "$ES_BOND" master "$ES_BRIDGE"
bridge vlan add dev "$ES_BOND" vid 10
bridge vlan add dev "$ES_BOND" vid 20

vtysh \
    -c "configure terminal" \
    -c "interface ${ES_BOND}" \
    -c "evpn mh es-id ${ES_ID}" \
    -c "evpn mh es-sys-mac ${ES_MAC}" \
    -c "evpn mh es-df-pref ${ES_DF_PREF}" \
    -c "end" \
    -c "write memory"

echo "=== ${LEAF} setup completed ==="