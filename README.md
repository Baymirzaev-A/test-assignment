## Лаба: Leaf-Spine, EVPN/VXLAN, FRR
Проект сетевой инфраструктуры для нового ЦОД заказчика. Заказчик — компания, предоставляющая услуги SaaS-платформы. Особенности:
  - Часть серверов — обычные веб-фермы (L2/L3).
  - Часть серверов — кластеры с высокими требованиями к восточно-западному трафику (низкая задержка, отсутствие потерь).
  - Есть отдельный сегмент для out-of-band управления.
  - Требуется изоляция арендаторов (multi-tenancy) на уровне L3.
  - Стек маршрутизации — FRR (opensource).
  
### <span style="color:red">Требуется спроектировать и развернуть воспроизводимую топологию, которая удовлетворяет требованиям заказчика.</span>

## Статус работы

| Этап | Компонент | Состояние |
|------|-----------|-----------|
| 1 | Underlay (eBGP, ECMP, loopback'и) | в работе |
| 2 | Overlay (EVPN/VXLAN, Type-2/3/5) | TBD |
| 3 | Multi-tenancy (VRF, пересекающиеся подсети) | TBD |
| 4 | EVPN Multihoming / MLAG | TBD |
| 5 | Anycast Gateway, DSCP/CoS, MTU 9000+ | TBD |
| 6 | OOB-VRF, Border/Gateway | TBD |

## Схема инфры (HLD)
```mermaid
graph TD
    GW["Gateway<br/>AS 65000<br/>(border)"]

    S1["Spine-1<br/>AS 65001"]
    S2["Spine-2<br/>AS 65001"]

    L1["Leaf-1<br/>AS 65111"]
    L2["Leaf-2<br/>AS 65112"]
    L3["Leaf-3<br/>AS 65113"]
    L4["Leaf-4<br/>AS 65114"]

    GW ---|eBGP /31| S1
    GW ---|eBGP /31| S2

    S1 ---|eBGP /31| L1
    S1 ---|eBGP /31| L2
    S1 ---|eBGP /31| L3
    S1 ---|eBGP /31| L4

    S2 ---|eBGP /31| L1
    S2 ---|eBGP /31| L2
    S2 ---|eBGP /31| L3
    S2 ---|eBGP /31| L4

    L1 -.- H["Хосты: <br/>EVPN MH, MLAG,<br/>VRF клиентов, веб-ферма"]
    L2 -.- H
    L3 -.- H
    L4 -.- H
```
## Первичные обоснования

| Решение | Почему |
|---------|--------|
| **eBGP в underlay** | Масштабирование (best-path, без flooding), политики (route-map/communities), естественный ECMP в CLOS. Использование eBGP признано стандартным решением для ЦОД (RFC 7938). |
| **iBGP EVPN в overlay** | Стандартный способ L2/L3 stretch в ЦОД; Type-2 обеспечивает L2, Type-5 маршруты обеспечивают L3, а type-3 отвечает за обнаружение VTEP и помогает понять, куда напрявлять BUM-трафик. |
| **Один ASN у Spine (65001)** | Соответствует RFC 7938 (ASN pre-planning): упрощает ECMP, исключает path hunting |
| **Отдельные loopback'и (Router-ID и VTEP)** | Разделение underlay и overlay визуально и логически; VTEP-адреса не участвуют в underlay-маршрутизации. |