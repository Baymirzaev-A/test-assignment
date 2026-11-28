#!/bin/bash
set -euo pipefail

NODE="${1:?Usage: vrf-setup.sh NODE VTEP_IP RMAC}"
VTEP_IP="${2:?VTEP_IP is required}"
RMAC="${3:?RMAC is required}"

GW_MAC_A="aa:bb:00:00:00:01"
GW_MAC_B="aa:bb:00:00:00:02"

echo "=== VRF setup: ${NODE} / ${VTEP_IP} ==="

# --------------------------------------------------
# 1. Linux VRFs
# --------------------------------------------------

create_vrf() {
    local name="$1"
    local table="$2"

    if ! ip link show "$name" >/dev/null 2>&1; then
        ip link add "$name" type vrf table "$table"
    fi

    ip link set "$name" up
}

create_vrf tenant-a 5001
create_vrf tenant-b 5002

sysctl -w net.ipv4.ip_forward=1

# --------------------------------------------------
# 2. Router MAC on tenant bridges
# --------------------------------------------------

ip link set br-a address "$RMAC"
ip link set br-b address "$RMAC"

ip link set br-a up
ip link set br-b up

# --------------------------------------------------
# 3. L3VNI VLAN mapping
# --------------------------------------------------

configure_l3vni() {
    local bridge="$1"
    local vxlan="$2"
    local vlan="$3"
    local vni="$4"

    bridge vlan del dev "$bridge" vid "$vlan" self 2>/dev/null || true
    bridge vlan add dev "$bridge" vid "$vlan" self

    bridge vlan del dev "$vxlan" vid "$vlan" 2>/dev/null || true
    bridge vlan add dev "$vxlan" vid "$vlan"
    bridge vlan add dev "$vxlan" vid "$vlan" tunnel_info id "$vni"

    bridge vni del dev "$vxlan" vni "$vni" 2>/dev/null || true
    bridge vni add dev "$vxlan" vni "$vni"
}

configure_l3vni br-a vx-a 4091 5001
configure_l3vni br-b vx-b 4092 5002

# --------------------------------------------------
# 4. Create VLAN SVI
# --------------------------------------------------

create_svi() {
    local name="$1"
    local bridge="$2"
    local vlan="$3"
    local vrf="$4"

    if ! ip link show "$name" >/dev/null 2>&1; then
        ip link add link "$bridge" name "$name" type vlan id "$vlan"
    fi

    ip link set "$name" mtu 8950
    ip link set "$name" address "$RMAC"
    ip link set "$name" master "$vrf"
    ip link set "$name" up
}

# Tenant A L2 SVIs
create_svi br-a.10 br-a 10 tenant-a
create_svi br-a.20 br-a 20 tenant-a

# Tenant B L2 SVIs
create_svi br-b.10 br-b 10 tenant-b
create_svi br-b.20 br-b 20 tenant-b

# L3VNI SVIs: no IP addresses
create_svi br-a.4091 br-a 4091 tenant-a
create_svi br-b.4092 br-b 4092 tenant-b

# --------------------------------------------------
# 5. Anycast Gateway
# --------------------------------------------------

create_anycast_gateway() {
    local name="$1"
    local parent="$2"
    local vrf="$3"
    local mac="$4"
    local address="$5"

    ip link del "$name" 2>/dev/null || true

    ip link add "$name" link "$parent" type macvlan mode private
    ip link set "$name" address "$mac"
    ip link set "$name" master "$vrf"
    ip addr replace "$address" dev "$name"
    ip link set "$name" up
}

if [[ "$NODE" != "gateway" ]]; then

    create_anycast_gateway gw-a10 br-a.10 tenant-a \
        "$GW_MAC_A" 172.16.10.1/24

    create_anycast_gateway gw-a20 br-a.20 tenant-a \
        "$GW_MAC_A" 172.16.20.1/24

    create_anycast_gateway gw-b10 br-b.10 tenant-b \
        "$GW_MAC_B" 172.16.10.1/24

    create_anycast_gateway gw-b20 br-b.20 tenant-b \
        "$GW_MAC_B" 172.16.20.1/24

    bridge fdb replace "$GW_MAC_A" dev br-a self local
    bridge fdb replace "$GW_MAC_B" dev br-b self local
fi

# --------------------------------------------------
# 6. FRR VRF / L3VNI / EVPN
# --------------------------------------------------

vtysh \
    -c "configure terminal" \
    -c "vrf tenant-a" \
    -c "vni 5001" \
    -c "exit-vrf" \
    -c "vrf tenant-b" \
    -c "vni 5002" \
    -c "exit-vrf" \
    -c "router bgp 64999" \
    -c "address-family l2vpn evpn" \
    -c "advertise-svi-ip" \
    -c "exit-address-family" \
    -c "exit" \
    -c "router bgp 64999 vrf tenant-a" \
    -c "address-family ipv4 unicast" \
    -c "rd ${VTEP_IP}:5001 \
    -c "redistribute connected" \
    -c "exit-address-family" \
    -c "address-family l2vpn evpn" \
    -c "route-target import 64999:5001" \
    -c "route-target export 64999:5001" \
    -c "advertise ipv4 unicast" \
    -c "exit-address-family" \
    -c "exit" \
    -c "router bgp 64999 vrf tenant-b" \
    -c "address-family ipv4 unicast" \
    -c "rd ${VTEP_IP}:5002 \
    -c "redistribute connected" \
    -c "exit-address-family" \
    -c "address-family l2vpn evpn" \
    -c "route-target import 64999:5002" \
    -c "route-target export 64999:5002" \
    -c "advertise ipv4 unicast" \
    -c "exit-address-family" \
    -c "exit" \
    -c "end" \
    -c "write memory"

echo "=== VRF / EVPN setup completed: ${NODE} ==="