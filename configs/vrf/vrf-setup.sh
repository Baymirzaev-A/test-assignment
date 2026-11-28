1 address "$RMAC" addrgenmode none
ip link set br-a.4091 master tenant-a
ip link set br-a.4091 up

ip link add link br-b name br-b.4092 type vlan id 4092
ip link set br-b.4092 address "$RMAC" addrgenmode none
ip link set br-b.4092 master tenant-b
ip link set br-b.4092 up

# --------------------------------------------------
# 8. Anycast Gateway
#    Gateway itself has no server-facing SVI IPs
# --------------------------------------------------

create_anycast_gateway() {
    local name="$1"
    local parent="$2"s
    local vrf="$3"
    local mac="$4"
    local address="$5"

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

    # Local FDB: Anycast MACs terminate locally on this VTEP
    bridge fdb replace "$GW_MAC_A" dev br-a self local
    bridge fdb replace "$GW_MAC_B" dev br-b self local
fi

# --------------------------------------------------
# 9. FRR VRF / L3VNI / EVPN configuration
# --------------------------------------------------

vtysh \
    -c "configure terminal" \
    \
    -c "vrf tenant-a" \
    -c "vni 5001" \
    -c "exit-vrf" \
    \
    -c "vrf tenant-b" \
    -c "vni 5002" \
    -c "exit-vrf" \
    \
    -c "router bgp 64999" \
    -c "address-family l2vpn evpn" \
    -c "advertise-svi-ip" \
    -c "exit-address-family" \
    -c "exit" \
    \
    -c "router bgp 64999 vrf tenant-a" \
    -c "address-family ipv4 unicast" \
    -c "redistribute connected" \
    -c "exit-address-family" \
    -c "address-family l2vpn evpn" \
    -c "route-target import 64999:5001" \
    -c "route-target export 64999:5001" \
    -c "advertise ipv4 unicast" \
    -c "exit-address-family" \
    -c "exit" \
    \
    -c "router bgp 64999 vrf tenant-b" \
    -c "address-family ipv4 unicast" \
    -c "redistribute connected" \
    -c "exit-address-family" \
    -c "address-family l2vpn evpn" \
    -c "route-target import 64999:5002" \
    -c "route-target export 64999:5002" \
    -c "advertise ipv4 unicast" \
    -c "exit-address-family" \
    -c "exit" \
    \
    -c "end" \
    -c "write memory"

echo "=== VRF / EVPN setup completed: ${NODE} ==="