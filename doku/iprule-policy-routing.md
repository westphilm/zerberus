# Routing-Policy (`ip rule`) – Zerberus Gateway

## Kontext

Dieses Gateway nutzt **Policy Routing** (`ip rule` + mehrere Routing-Tabellen), um WireGuard, NordVPN und lokalen Traffic strikt und nachvollziehbar zu trennen.
Ziel ist **stabile WG-Konnektivität**, **VPN-erzwungener Internet-Traffic** und **kein WAN-Leak** – bei gleichzeitigem Zugriff auf lokale Netze.

### Wo definiert?
- `src/system/usr/local/sbin/pi-boot-network-base.sh`
- `src/system/usr/local/sbin/nordvpn-start.sh`
- `src/system/usr/local/sbin/nordvpn-stop.sh`

siehe außerdem:
- [NFTables](nftables.md)
- [Wireguard / wg0.service](wireguard.md)

Die folgende Liste dokumentiert **alle relevanten IPv4-Routing-Rules** in ihrer effektiven Bedeutung.  
Die Reihenfolge (Priority) ist entscheidend.

---

## Rule 45

```
45: from all fwmark 0x77 lookup main
```

Leitet allen Traffic mit `fwmark 0x77` explizit über die Routing-Tabelle `main`.
Wird für **WireGuard-Steuerverkehr** (Handshake, Keepalive) genutzt, damit dieser niemals über das VPN geroutet wird.
Verhindert instabile oder abbrechende WG-Verbindungen bei aktivem VPN.

---

## Rule 90

```
90: from all to 10.6.0.0/24 lookup main
```

Stellt sicher, dass Traffic **zum WireGuard-Netz** (`wg0`, inkl. Gateway und Peers) immer über `main` geroutet wird.
Verhindert Fehlrouting von Antworten oder internen WG-Paketen ins VPN.
Grundlage für zuverlässige Erreichbarkeit von WG-Clients und lokalen Diensten.

---

## Rule 95

```
95: from 10.6.0.0/24 lookup vpn
```

Leitet sämtlichen Traffic **vom WireGuard-Clientnetz** standardmäßig in die VPN-Routingtabelle.
Erzwingt: *WG-Clients → Internet über VPN*.
Ausnahmen (LAN / lokale Netze) werden **innerhalb der VPN-Tabelle** über explizite Routen geregelt.

---

## Rule 110

```
110: from all fwmark 0x520 lookup vpn
```

Leitet allen Traffic mit `fwmark 0x520` in die VPN-Routingtabelle.
Dieses Mark kennzeichnet **VPN-Nutzdaten** (z. B. von LAN-Clients), die gezielt über `nordlynx` geroutet werden sollen.
Ermöglicht eine saubere Trennung zwischen VPN-Payload und nicht-VPN-Traffic.

---

## Rule 1000

```
1000: from 192.168.50.0/24 lookup vpn
```

Leitet Traffic aus dem internen LAN (`eth1`) standardmäßig in die VPN-Routingtabelle.
Erzwingt VPN-Nutzung für LAN-Clients auf Routing-Ebene.
WAN-Fallback ist nur über explizite Killswitch-Ausnahmen möglich.

---

## Rule 32760

```
32760: from all to 169.254.0.0/16 lookup main
```

Stellt sicher, dass **Link-Local-Traffic** (z. B. ARP-nahe Protokolle, lokale Autokonfiguration) niemals über VPN oder alternative Tabellen läuft.
Verhindert Routing-Anomalien bei Kernel- oder Interface-internem Verkehr.

---

## Rule 32761

```
32761: from all to 192.168.0.0/16 lookup main
```

Leitet Traffic zu privaten Netzen im Bereich `192.168.0.0/16` immer über `main`.
Garantiert korrekten Zugriff auf lokale Infrastruktur (Fritzbox, LAN, Management).
Schützt vor versehentlichem VPN-Tunneling lokaler Ziele.

---

## Rule 32762

```
32762: from all to 172.16.0.0/12 lookup main
```

Sichert korrektes Routing zu privaten Netzen im Bereich `172.16.0.0/12`.
Relevant für Docker-, VM- oder weitere interne Netze.
Verhindert, dass RFC1918-Ziele fälschlich ins VPN laufen.

---

## Rule 32763

```
32763: from all to 10.0.0.0/8 lookup main
```

Leitet Traffic zu privaten Netzen im Bereich `10.0.0.0/8` über `main`.
Erfasst zusätzliche interne Netze, Tunnel oder zukünftige Erweiterungen.
Teil der generellen RFC1918-Schutzlogik.

---

## Rule 32764

```
32764: from all lookup main suppress_prefixlength 0
```

Unterdrückt automatisch hinzugefügte Kernel-Routen beim Lookup in `main`.
Verhindert unerwartete Seiteneffekte durch implizite Präfixe.
Sorgt für deterministisches, kontrolliertes Routing-Verhalten.

---

## Rule 32766

```
32766: from all lookup main
```

Fallback-Regel: leitet sämtlichen verbleibenden Traffic über die Standard-Routingtabelle `main`.
Wird nur erreicht, wenn keine vorherige Rule greift.
Garantiert immer ein definiertes Routing-Verhalten.

---

