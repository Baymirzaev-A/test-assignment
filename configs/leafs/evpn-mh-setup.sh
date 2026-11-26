#!/bin/sh
set -eu

BOND="${1:?bond name required}"
ES_ID="${2:?ES-ID required}"
ES_MAC="${3:?ES system MAC required}"
BR10="${4:?VLAN 10 bridge required}"
BR20="${5:?VLAN 20 bridge required}"

# Remove old VLAN interfaces from the physical port.
for vlan in 10 20; do
    OLD="eth4.$vlan"
    if ip link show "$OLD" >/dev/null 2>&1; then
        ip link set "$OLD" nomaster 2>/dev/null || true
        ip link delete "$OLD"
    fi
done

ip link set eth4 down

# Create the Leaf-side LACP bond.
if ! ip link show "$BOND" >/dev/null 2>&1; then
    ip link add "$BOND" type bond mode 802.3ad
fi

ip link set "$BOND" down
ip link set "$BOND" type bond \
    mode 802.3ad \
    miimon 100 \
    lacp_rate fast \
    xmit_hash_policy layer2+3 \
    ad_actor_sys_prio 100 \
    ad_actor_system "$ES_MAC"

ip link set "$BOND" address "$ES_MAC"
ip link set "$BOND" mtu 9000

ip link set eth4 nomaster 2>/dev/null || true
ip link set eth4 mtu 9000
ip link set eth4 master "$BOND"

ip link set eth4 up
ip link set "$BOND" up

# Recreate VLANs on the bond and attach to the original tenant bridges.
for vlan in 10 20; do
    if ! ip link show "$BOND.$vlan" >/dev/null 2>&1; then
        ip link add link "$BOND" name "$BOND.$vlan" type vlan id "$vlan"
    fi

    ip link set "$BOND.$vlan" mtu 8950
done

ip link set "$BOND.10" master "$BR10"
ip link set "$BOND.20" master "$BR20"
ip link set "$BOND.10" up
ip link set "$BOND.20" up

# Configure the EVPN Ethernet Segment in FRR.
vtysh \
    -c "configure terminal" \
    -c "interface $BOND" \
    -c "evpn mh es-id $ES_ID" \
    -c "evpn mh es-sys-mac $ES_MAC" \
    -c "end" \
    -c "write memory"

echo "Configured $BOND: ES-ID=$ES_ID, ES-MAC=$ES_MAC"