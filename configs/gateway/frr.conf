frr version 10.2.1
frr defaults traditional
hostname gateway
log syslog informational
service integrated-vtysh-config
!
router bgp 65000
 bgp router-id 10.0.0.100
 no bgp default ipv4-unicast
 no bgp ebgp-requires-policy

 neighbor 192.168.255.1 remote-as 65001
 neighbor 192.168.255.3 remote-as 65001
 !
 address-family ipv4 unicast
  network 10.0.0.100/32
  neighbor 192.168.255.1 activate
  neighbor 192.168.255.3 activate
 exit-address-family
!
line vty
!