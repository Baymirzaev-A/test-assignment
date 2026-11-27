#!/bin/sh
#
# Classic MLAG server-side interface setup.
#
# Usage:
#   sh configs/mlag/mlag-setup.sh leaf-1
#   sh configs/mlag/mlag-setup.sh leaf-2
#   sh configs/mlag/mlag-setup.sh leaf-3
#   sh configs/mlag/mlag-setup.sh leaf-4
#
# eth5 -> bond-mlag-a -> br-a (Tenant A)
# eth6 -> bond-mlag-b -> br-b (Tenant B)
#
# eth4 / EVPN Multihoming bonds are NOT touched.

set -eu

LEAF="${1:-}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root"
    exit 1
fi

case "$LEAF" in
    leaf-1|leaf-2)
        ACTOR_SYSTEM="02:00:00:00:12:01"
        ;;
    leaf-3|leaf-4)
        ACTOR_SYSTEM="02:00:00:00:34:01"
        ;;
    *)
        echo "Usage: $0 leaf-1|leaf-2|leaf-3|leaf-4"
        exit 1
        ;;
esac

BOND_A="bond-mlag-a"
BOND_B="bond-mlag-b"

BRIDGE_A="br-a"
BRIDGE_B="br-b"

PORT_A="eth5"
PORT_B="eth6"

MTU="9000"

log() {
    echo "[mlag-setup] $*"
}

die() {
    echo "[mlag-setup] ERROR: $*" >&2
    exit 1
}

link_exists() {
    ip link show dev "$1" >/dev/null 2>&1
}

require_link() {
    link_exists "$1" || die "Interface $1 does not exist"
}

set_bond_attribute() {
    bond="$1"
    attribute="$2"
    value="$3"
    path="/sys/class/net/$bond/bonding/$attribute"

    [ -e "$path" ] || die \
        "Required bonding attribute is unavailable: $path"

    echo "$value" > "$path"
}

create_bond() {
    bond="$1"
    actor_key="$2"
    port="$3"
    bridge="$4"

    log "Configuring $bond: $port -> $bridge"

    require_link "$port"
    require_link "$bridge"

    # Remove the physical interface from its previous bridge.
    ip link set dev "$port" down
    ip link set dev "$port" nomaster 2>/dev/null || true

    # Create the bond if it does not exist.
    if ! link_exists "$bond"; then
        ip link add name "$bond" type bond \
            mode 802.3ad \
            miimon 100 \
            lacp_rate fast \
            xmit_hash_policy layer2+3
    fi

    # Configure the LACP identity before attaching the slave.
    set_bond_attribute "$bond" mode 802.3ad
    set_bond_attribute "$bond" miimon 100
    set_bond_attribute "$bond" lacp_rate 1
    set_bond_attribute "$bond" xmit_hash_policy layer2+3
    set_bond_attribute "$bond" ad_actor_system "$ACTOR_SYSTEM"
    set_bond_attribute "$bond" ad_actor_sys_prio 65535
    set_bond_attribute "$bond" ad_user_port_key "$actor_key"

    # Set MTU before attaching the physical interface.
    ip link set dev "$port" mtu "$MTU"
    ip link set dev "$bond" mtu "$MTU"

    # Attach physical port to bond.
    ip link set dev "$port" master "$bond"

    # Attach bond to the tenant bridge.
    ip link set dev "$bond" master "$bridge"

    # The server-facing bond is a tagged trunk:
    # VLAN 10 and VLAN 20 are carried into the tenant bridge.
    bridge vlan add dev "$bond" vid 10
    bridge vlan add dev "$bond" vid 20

    ip link set dev "$bond" up
    ip link set dev "$port" up

    log "$bond configured successfully"
}

log "Starting MLAG interface setup on $LEAF"
log "Shared LACP actor system: $ACTOR_SYSTEM"

require_link eth3
require_link eth4
require_link eth5
require_link eth6
require_link br-a
require_link br-b

# Pair-specific peer-link is eth3.
# It is intentionally not configured by this script.

# Tenant A server-facing LAG.
create_bond "$BOND_A" 101 "$PORT_A" "$BRIDGE_A"

# Tenant B server-facing LAG.
create_bond "$BOND_B" 102 "$PORT_B" "$BRIDGE_B"

log "Resulting interfaces:"
ip -br link show "$BOND_A"
ip -br link show "$BOND_B"

log "Bridge membership:"
bridge link show

log "VLAN membership:"
bridge vlan show

log "MLAG interface setup completed on $LEAF"