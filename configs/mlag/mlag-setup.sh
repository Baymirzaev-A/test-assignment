#!/bin/bash
set -euo pipefail

LEAF="${1:-}"

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

MTU=9000

log() {
    echo "[MLAG] $*"
}

require_iface() {
    ip link show dev "$1" >/dev/null 2>&1 || {
        echo "ERROR: interface $1 does not exist"
        exit 1
    }
}

create_mlag_bond() {
    local bond="$1"
    local port="$2"
    local bridge="$3"
    local key="$4"
    local key_path="/sys/class/net/$bond/bonding/ad_user_port_key"

    log "Configuring $bond: $port -> $bridge, key=$key"

    require_iface "$port"
    require_iface "$bridge"

    # Detach the physical port from any previous master.
    ip link set dev "$port" down
    ip link set dev "$port" nomaster 2>/dev/null || true

    # Create bond if it does not exist.
    if ! ip link show dev "$bond" >/dev/null 2>&1; then
        ip link add name "$bond" type bond mode 802.3ad
    fi

    # Bond must be down before configuring LACP identity.
    ip link set dev "$bond" down

    ip link set dev "$bond" type bond \
        mode 802.3ad \
        miimon 100 \
        lacp_rate fast \
        xmit_hash_policy layer2+3 \
        ad_actor_system "$ACTOR_SYSTEM"

    ip link set dev "$bond" mtu "$MTU"

    # Set user port key before attaching the physical port.
    [[ -e "$key_path" ]] || {
        echo "ERROR: missing sysfs attribute: $key_path" >&2
        exit 1
    }

    printf '%s\n' "$key" > "$key_path"

    local actual_key
    actual_key=$(cat "$key_path")

    [[ "$actual_key" == "$key" ]] || {
        echo "ERROR: $bond expected key $key, got $actual_key" >&2
        exit 1
    }

    log "$bond LACP user port key: $actual_key"

    # Attach physical server port to bond.
    ip link set dev "$port" mtu "$MTU"
    ip link set dev "$port" master "$bond"

    # Attach bond to tenant bridge.
    ip link set dev "$bond" master "$bridge"

    # Tagged server trunk: VLAN 10 and VLAN 20.
    bridge vlan add dev "$bond" vid 10 2>/dev/null || true
    bridge vlan add dev "$bond" vid 20 2>/dev/null || true

    ip link set dev "$port" up
    ip link set dev "$bond" up

    log "$bond configured successfully"
}

log "Starting MLAG server interface setup on $LEAF"
log "Shared LACP System ID: $ACTOR_SYSTEM"

require_iface eth3
require_iface eth4
require_iface eth5
require_iface eth6
require_iface br-a
require_iface br-b

# Tenant A:
# srv-mlag-01 or srv-mlag-03
create_mlag_bond bond-mlag-a eth5 br-a 101

# Tenant B:
# srv-mlag-02 or srv-mlag-04
create_mlag_bond bond-mlag-b eth6 br-b 102

log "MLAG bonds:"
ip -d link show bond-mlag-a
ip -d link show bond-mlag-b

log "Bridge membership:"
bridge link show

log "VLAN membership:"
bridge vlan show

log "MLAG server interfaces configured"