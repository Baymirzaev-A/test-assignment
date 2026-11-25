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

Ожидаемый результат: маршруты до 10.0.1.1/32 (Leaf-1), 10.0.1.2/32 (Leaf-2), 10.0.1.3/32 (Leaf-3), 10.0.1.4/32 (Leaf-4), 10.0.0.100/32 (Gateway) с next-hop через соответствующие /31-линки.

```bash
docker exec -it clab-dc-fabric-leaf-1 ping -I 10.0.1.1 -c 4 10.0.1.2
```
Если не указать source, то пинг пойдет с ip 192.168.1.1 или 192.168.2.1, а так как мы не анонсируем стыковочные сети в bgp, ответ от 10.0.1.2 не придет.
```bash
docker exec -it clab-dc-fabric-leaf-1 vtysh -c "show ip route 10.0.0.100/32"
```
Ожидаемый результат: два next-hop (через Spine-1 и Spine-2), например 192.168.1.0 и 192.168.2.0

**Теперь проверяем оверлэй**

docker exec -it clab-dc-fabric-leaf-1 vtysh -c "show evpn vni"

## Остановка и удаление лабы.

```bash
sudo containerlab destroy -t topology/dc-mini.clab.yml --cleanup
```
