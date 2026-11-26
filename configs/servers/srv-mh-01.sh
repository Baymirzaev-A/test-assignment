#!/bin/sh
set -eu

apk add --no-cache iproute2

BOND="bond0"

for dev in eth1 eth2; do
    ip link set "$dev" down
    ip link set "$dev" nomaster 2>/dev/null || true
done

if ! ip link show "$BOND" >/dev/null 2>&1; then
    ip link add "$BOND" type bond mode 802.3ad
fi

ip link set "$BOND" down || true
ip link set "$BOND" type bond mode 802.3ad \
    miimon 100 \
    lacp_rate fast \
    xmit_hash_policy layer2+3

ip link set "$BOND" mtu 9000

for dev in eth1 eth2; do
    ip link set "$dev" mtu 9000
    ip link set "$dev" master "$BOND"
    ip link set "$dev" up
done

ip link set "$BOND" up

for vlan in 10 20; do
    if ! ip link show "${BOND}.${vlan}" >/dev/null 2>&1; then
        ip link add link "$BOND" \
            name "${BOND}.${vlan}" type vlan id "$vlan"
    fi

    ip link set "${BOND}.${vlan}" mtu 8950 up
done

echo "=== $(hostname): LACP bond configured ==="

ip -d link show "$BOND"
cat /proc/net/bonding/"$BOND"