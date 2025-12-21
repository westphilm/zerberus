## Laufzeit-Analyse von Routing & Traffic-Pfaden

Dieses Kapitel beschreibt, wie die **relevanten Routing-Entscheidungen zur Laufzeit kompakt und verlässlich überprüft** werden können. Die Befehle sind bewusst auf das Wesentliche reduziert und decken Policy Routing, WireGuard, nftables und NAT ab.

---

## 1) Policy Routing – Entscheidungslogik

```bash
ip -4 rule
```

Zeigt die **Reihenfolge und Priorität** aller Policy-Routing-Regeln.
Relevant sind insbesondere:

* `fwmark 0x77  lookup main`  (WireGuard-Steuerverkehr)
* `to 10.6.0.0/24 lookup main` (WireGuard-Tunnelnetz)
* `fwmark 0x520 lookup vpn`   (VPN-Nutzdaten)

Gefiltert:

```bash
ip -4 rule | grep -E '0x77|0x520|10.6.0.0'
```

---

## 2) Routing-Tabellen selbst

```bash
ip -4 route show table main
ip -4 route show table vpn
ip -4 route show table wan
```

Beantwortet die Frage:

> *„Wohin würde der Traffic gehen, **wenn diese Tabelle greift**?“*

---

## 3) Konkrete Routing-Entscheidung simulieren (Goldstandard)

```bash
ip -4 route get <ZIEL-IP>
ip -4 route get <ZIEL-IP> mark 0x77
ip -4 route get <ZIEL-IP> mark 0x520
```

Beispiele:

```bash
ip -4 route get 1.1.1.1
ip -4 route get 1.1.1.1 mark 0x520
ip -4 route get 10.6.0.2
```

→ zeigt **exakt**, welches Interface und Gateway tatsächlich verwendet würden.

---

## 4) WireGuard-Status (Control vs. Tunnel)

```bash
wg show
```

Wichtige Punkte:

* `fwmark: 0x77`
* `latest handshake`
* `transfer rx/tx`

Damit lässt sich klar trennen zwischen:

* WireGuard-Steuerverkehr
* WireGuard-Tunnel-Nutzdaten

---

## 5) nftables – Killswitch & Zählung

```bash
nft list chain ip filter FORWARD
nft list counter ip filter c_drop_generic
```

Live-Beobachtung:

```bash
watch -n1 'nft list counter ip filter c_drop_generic'
```

Steigende Werte bedeuten:

* WAN-Traffic wurde **erfolgreich blockiert** (Killswitch greift)

---

## 6) NAT-Überprüfung (Leak-Kontrolle)

```bash
nft list counter ip nat c_masq_wan_bytes
nft list counter ip nat c_masq_vpn_bytes
```

Interpretation:

* **Killswitch aktiv** → `c_masq_wan_bytes` bleibt stabil
* **VPN aktiv** → ausschließlich `c_masq_vpn_bytes` steigt

---

## Merksatz

> **`ip rule` sagt *wer entscheidet*,**
> **`ip route get` sagt *was wirklich passiert*,**
> **nft-Counter sagen *ob es passiert ist*.**

Dieses Set an Checks bildet die empfohlene Standard-Diagnose für Betrieb, Monitoring und Fehlersuche.
