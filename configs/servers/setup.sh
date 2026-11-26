#!/bin/sh
set -eu

# Install full iproute2; Alpine's BusyBox ip is insufficient.
apk add --no-cache iproute2

# Physical links from Containerlab.
for dev in eth1 eth2; do
    ip link set dev "$dev" down
    ip link set dev "$dev" mtu 9000
done

# Create the server-side LACP bond once.
if ! ip link show bond0 >/dev/null 2>&1; then
    ip link add bond0 type bond mode 802.3ad
fi

ip link set bond0 down
ip link set bond0 type bond \
    mode 802.3ad \
    miimon 100 \
    lacp_rate fast \
    xmit_hash_policy layer2+3 \
    ad_actor_sys_prio 65534

ip link set bond0 mtu 9000

# Attach both NICs to the bond.
for dev in eth1 eth2; do
    ip link set dev "$dev" nomaster 2>/dev/null || true
    ip link set dev "$dev" master bond0
    ip link set dev "$dev" mtu 9000
done

ip link set eth1 up
ip link set eth2 up
ip link set bond0 up

# Tenant VLANs remain separate L2 interfaces.
for vlan in 10 20; do
    if ! ip link show "bond0.$vlan" >/dev/null 2>&1; then
        ip link add link bond0 name "bond0.$vlan" type vlan id "$vlan"
    fi

    ip link set "bond0.$vlan" mtu 8950
    ip link set "bond0.$vlan" up
done

echo "Server LACP bond and VLANs configured:"
ip -d link show bond0
ip -d link show bond0.10
ip -d link show bond0.20