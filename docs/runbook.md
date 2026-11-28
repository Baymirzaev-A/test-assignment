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
Если не указать source, то пинг пойдет с ip 192.168.1.1 или 192.168.2.1, а так как мы не анонсируем p2p сети в bgp, ответ от 10.0.1.2 не придет.
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

**Проверка LACP на Leaf** 


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

**Далее проверка mlag**

```bash
for i in 1 2 3 4; do
  echo "Leaf-$i"
  docker exec clab-dc-fabric-leaf-$i \
   ip -br link show
done

```
Должны появиться bond-mlag-a и bond-mlag-b.

Теперь проверяем соответствие вланов бондам, у каждого бонда должен быть влан 10 и 20.

```bash
for i in 1 2 3 4; do
  echo "========== LEAF-$i =========="
  docker exec clab-dc-fabric-leaf-$i bridge link show
  docker exec clab-dc-fabric-leaf-$i bridge vlan show
done
```

Надо проверить как отработал python скрипт.

```bash
for i in 1 2 3 4; do   
echo "========== LEAF-$i ==========";   
docker exec clab-dc-fabric-leaf-$i sh -c     'pgrep -af mlagd; 
echo "--- LOG ---"; cat /var/log/mlagd.log'; 
done
```
Тут нас интересует строка *State=ACTIVE peer_alive=True peer_link_up=True forwarding=True*
НО обязательно будут и строки hertbeat failed из-за кривой и неполной реализации.

### Тест на отключение линка одного сервера
```bash
docker exec clab-dc-fabric-srv-mlag-01 ip link set eth1 down

docker exec clab-dc-fabric-srv-mlag-01 cat /proc/net/bonding/bond0
```

после этого смотрим, что один интерфейс лежит, LACP aggregator работает (было два порта, стало 1, MII статаус как был up, так и остался)

Теперь тестим отключение пир-линка:
```bash
 docker exec clab-dc-fabric-leaf-1 ip link set eth3 down
```

```bash
docker exec clab-dc-fabric-leaf-1 \
  sh -c 'tail -n 40 /var/log/mlagd.log'
```
И видим 
*State=PRIMARY_DEGRADED peer_alive=True peer_link_up=False forwarding=True*

То есть остался ACTOR
```bash
for i in 1 2; do
  echo "===== LEAF-$i ====="
  for b in bond-mlag-a bond-mlag-b; do
    echo "--- $b ---"
    docker exec clab-dc-fabric-leaf-$i ip -br link show dev "$b"
  done
done
```
И видим что на LEAF 1 бонд в UP, а в leaf 2 - down.
Можем включить
```bash
 docker exec clab-dc-fabric-leaf-1 ip link set eth3 up
```

## Тестируем VRF и L3VNI

```bash
 for node in leaf-1 leaf-2 leaf-3 leaf-4 gateway; do
    echo "========== $node =========="
    docker exec clab-dc-fabric-$node \
        vtysh -c "show vrf vni"
done
```
Тут видим создались ли VRF:
tenant-a - 5001 - vx-a - br-a.4091 - установился ли RMAC

Создались ли vrf таблицы 5001 и 5002
```bash
docker exec clab-dc-fabric-leaf-1 ip -d link show type vrf
```

Смотрим все интерфейсы
```bash
docker exec clab-dc-fabric-leaf-1 ip -br link
```

И сетки у каждого tenant 
```bash
 docker exec clab-dc-fabric-leaf-1 \
    vtysh -c "show ip route vrf tenant-a"
```
```bash
 docker exec clab-dc-fabric-leaf-1 \
    vtysh -c "show ip route vrf tenant-b"
```

## Остановка и удаление лабы.

```bash
sudo containerlab destroy -t topology/dc.clab.yml --cleanup
```
