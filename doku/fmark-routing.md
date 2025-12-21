## Traffic-Markierung & Routing-Zuordnung (Grundprinzip)

Dieses Gateway nutzt **Policy Routing mit Firewall-Marks (fwmark)**, um unterschiedliche Traffic-Arten **eindeutig, deterministisch und leak-frei** zu behandeln.
Ziel ist eine klare Trennung zwischen:

- **Tunnel-Steuerverkehr**
- **VPN-Nutzdaten**
- **lokalem / internem Traffic**

---

## Abstract

Bestimmter Traffic wird **frühzeitig markiert** (`fwmark`) und anschließend über **dedizierte Routing-Regeln** in die passende Routing-Tabelle geleitet.
So wird vermieden, dass sich Tunnel-Steuerverkehr, VPN-Payload und Fallback-Routen gegenseitig beeinflussen.

---

## Traffic-Marker

### `fwmark 0x77` — WireGuard-Steuerverkehr

- gesetzt in **`/etc/wireguard/wg0.conf`**

- Gilt ausschließlich für **WireGuard selbst** (`wg0`)
- Umfasst:
  - Handshake
  - Keepalives
  - Tunnel-Management
- Wird **direkt im WireGuard-Interface gesetzt**:

```ini
# /etc/wireguard/wg0.conf
[Interface]
FwMark = 0x77
```

👉 Dieser Traffic **darf nicht über das VPN** laufen, sondern muss zuverlässig über das **WAN-Routing** erreichbar sein.

**Routing-Regel** (dauerhaft, beim Boot, siehe **`pi-boot-network-base.sh`** ):

```bash
fwmark 0x77 → lookup main
```

---

### `fwmark 0x520` — VPN-Nutzdaten

- gesetzt in **`nordvpn-start.sh`**
- Markiert **sämtlichen Traffic**, der **über NordVPN** ins Internet soll
- Wird über nftables / Routing-Skripte gesetzt
- Routing erfolgt **ausschließlich über die VPN-Routing-Tabelle**

```bash
fwmark 0x520 → lookup vpn
```
👉 Ergebnis:
- Kein Fallback ins WAN
- Kein IP-Leak bei VPN-Ausfall (Killswitch greift zusätzlich)

---

## Ergebnis

- ✔ **WireGuard bleibt jederzeit erreichbar**, unabhängig vom VPN-Status
- ✔ **VPN-Traffic verlässt das System ausschließlich über NordVPN**
- ✔ **Routing ist stabil, reproduzierbar und nachvollziehbar**
- ✔ **Start/Stop-Skripte bleiben schlank & unabhängig** (keine dynamischen Korrekturen nötig)


---

## References

* [NFTables](nftables.md)
* [NordVPN](nordvpn.md)
* [WireGuard Service](wireguard.md)
