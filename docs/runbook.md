## Установка Docker и containerlab


```bash
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
```
После установки перелогинься (или выполни newgrp docker), чтобы работать с Docker без sudo.

```bash
git clone https://github.com/Baymirzaev-A/test-assignment.git
cd test-assignment

sudo containerlab deploy -t dc.clab.yml

sudo containerlab inspect -t dc.clab.yml
```
для тестов dc-mini.clab.yml
## Первичное тестирование (ручное)

```bash
docker exec -it clab-dc-fabric-spine-1 vtysh -c "show bgp summary"

docker exec -it clab-dc-fabric-spine-1 vtysh -c "show ip route bgp"
```

Ожидаемый результат: маршруты до 10.0.1.1/32 (Leaf-1), 10.0.1.2/32 (Leaf-2), 10.0.1.3/32 (Leaf-3), 10.0.1.4/32 (Leaf-4), 10.0.0.100/32 (Gateway) с next-hop через соответствующие /31-линки. Помимо это маршруты к 10.10.10.x/32. В выводе должны появиться IPv4 Unicast Summary и L2VPN EVPN Summary. 

```bash
docker exec -it clab-dc-fabric-leaf-1 ping -I 10.0.1.1 -c 4 10.0.1.2
```
Если не указать source, то пинг пойдет с ip 192.168.1.1 или 192.168.2.1, а так как мы не анонсируем стыковочные сети в bgp, ответ от 10.0.1.2 не придет.
```bash
docker exec -it clab-dc-fabric-leaf-1 vtysh -c "show ip route 10.0.0.100/32"
```
Ожидаемый результат: два next-hop (через Spine-1 и Spine-2), например 192.168.1.0 и 192.168.2.0
```bash
 docker exec clab-dc-fabric-leaf-1 vtysh -c "show bgp l2vpn evpn sum"
```
Здесь должны увидеть оба спайна, их AS64999

```bash
docker exec -it clab-dc-fabric-leaf-1 bash
```

Заходим в каждый контейнер лифа и проверяем
```bash
 ip -br link - создались ли бриджи и бонды
 bridge vni show и bridge vlan tunnel show - соответствие вланов и VNI
```

```bash
docker exec clab-dc-fabric-leaf-1 vtysh -c "show evpn vni"
```
Видим VNI

```bash
docker exec clab-dc-fabric-leaf-1 vtysh -c "show evpn vni 10010"
```
Для того, чтобы увидеть удаленные VTEP 

```bash
docker exec clab-dc-fabric-leaf-1 vtysh -c "show bgp l2vpn evpn route type 3"
```
смотрим, есть ли маршруты тип 3 с VTEP, тип 1 и 4 тоже должны быть.

Тип 1 и 4 отвечают за MH.

```bash
vtysh -c "show evpn es"
vtysh -c "show evpn es-evi"
```

Проверка LACP на Leaf 


```bash
for n in leaf-1 leaf-2 leaf-3 leaf-4; do
echo "===== $n: bond ====="
docker exec clab-dc-fabric-$n cat /proc/net/bonding/bond-mh01 2>/dev/null || true
docker exec clab-dc-fabric-$n cat /proc/net/bonding/bond-mh02 2>/dev/null || true
done
```

Sys mac add должен совпадать на парах leaf.

Теперь то же самое на серверах

```bash
for n in srv-mh-01 srv-mh-02 srv-mlag-01 srv-mlag-02 srv-mlag-03 srv-mlag-04; do
  echo "===== $n ====="
  docker exec clab-dc-fabric-$n cat /proc/net/bonding/bond0
done
```
Оба серверных аплинка входят в один агрегатор.

## Остановка и удаление лабы.

```bash
sudo containerlab destroy -t topology/dc-mini.clab.yml --cleanup
```
