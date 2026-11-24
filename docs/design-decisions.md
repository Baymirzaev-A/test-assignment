## 1. Underlay: eBGP по connected-стыкам, а не по loopback'ам


**eBGP по /31-стыкам (connected):**
1) Соответствует RFC 7938 - стандартное решение, 
2) Конфиг проще (нет статики и multihop), легче масштабируется. Сначала я планировал делать по loopback, но передумал. Если бы изначально я планировал ebgp по стыкам, то выбрал бы сетки /30, по-моему так было бы "чище".

### Overlay

Loopback VTEP (`10.10.10.X`) анонсируется в underlay через `network` в BGP, чтобы все узлы знали, как до него добраться. Это единственная роль loopback'ов в underlay — они не участвуют в установлении BGP-сессий, но должны быть доступны для VXLAN-туннелей.

## 2. BGP ASN-план

### Underlay (eBGP)

| Устройство | ASN |
|------------|-----|
| Gateway | 65000 |
| Spine-1 | 65001 |
| Spine-2 | 65001 |
| Leaf-1 | 65111 |
| Leaf-2 | 65112 |
| Leaf-3 | 65113 |
| Leaf-4 | 65114 |

Сначала я выбрал разные AS для спайнов, но потом в RFC увидел рекомендацию - для спайнов 1AS. При этом меньше конфиг (не нужна строка bgp bestpath as-path multipath-relax), Работает обычный механизм защиты от петель в eBGP - AS-PATH. Не копятся лишние пути.

### Overlay (iBGP EVPN)

| Компонент | ASN |
|-----------|-----|
| Overlay (все Leaf'ы и Gateway) | 64999 |

Одна общая AS для overlay. Spine'ы — Route Reflector'ы для iBGP EVPN. Сессии — по loopback'ам VTEP (`10.10.10.X`). Выбор 64999 (вне диапазона underlay-AS) сделан для визуального разделения underlay и overlay в конфигах и диагностике.

## 3. RT/RD

Раздел будет заполнен на этапе overlay: политика Route Target и Route Distinguisher
для L2VNI и L3VNI, auto vs manual.

## 4. DF election

Раздел будет заполнен на этапе EVPN Multihoming: механизм Designated Forwarder,
Type-4, ESI.

## 5. ESI

Раздел будет заполнен на этапе EVPN Multihoming: выбор ESI, All-Active vs Single-Active.

## 6. MLAG vs EVPN Multihoming

Раздел будет заполнен на этапе EVPN Multihoming: сравнение, почему в задании
требуются оба, где какой применяется.
