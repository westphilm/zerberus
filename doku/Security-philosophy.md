# Zerberus Gateway – Security & Privacy Philosophy

---

## A. Erweiterte Sicherheitsbetrachtung (interne Doku)

### Zielsetzung

Dieses Gateway verfolgt **kontrollierte Sicherheit und Privacy**, nicht maximale Anonymisierung.
Der Fokus liegt auf:

* klaren Verantwortlichkeiten
* messbaren Garantien
* minimaler Angriffsfläche
* sofort erkennbaren Abweichungen

---

### Was dieses Setup bewusst **nicht** schützt

Nicht vollständig vermeidbar sind:

* **Zielserver-Tracking**

    * Cookies, Logins, Browser-Fingerprinting
* **Langzeit-Metadatenanalyse**

    * Zeitpunkte, Frequenzen, Traffic-Volumen
* **Kooperative staatliche Akteure**

    * Korrelation aus ISP + VPN + DNS
* **Kompromittierte Endgeräte**

    * Malware, Keylogger, unsichere Apps
* **Anwendungsfehler**

    * Klartext-Protokolle, eigene DNS-Resolver

Diese Risiken lassen sich **nicht sinnvoll** rein netzwerkseitig eliminieren.

---

### Warum das akzeptabel ist

* hoher Aufwand, kein Massenangriff
* zielgerichtete Angriffe benötigen Kontext
* Gegenmaßnahmen sind **situativ** sinnvoller:

    * Tor über VPN
    * getrennte Browser-Profile
    * bewusste Nutzung

---

### Sicherheitsgarantien dieses Setups

Zerberus stellt sicher:

* kein DNS-Leak
* kein unbemerkter WAN-Fallback
* DNS ≠ VPN ≠ ISP (Informations-Trennung)
* Policy-Verletzungen sind **messbar**, nicht hypothetisch

Alle relevanten Pfade sind:

* gezählt
* protokolliert
* reproduzierbar

---

### Grundsatz

> **Absolute Anonymität ist unrealistisch.**
> **Kontrolle, Transparenz und Nachvollziehbarkeit sind erreichbar.**

---

## B. Kurzfassung für GitHub / README

### Zerberus Gateway – Security Overview

**Zerberus** ist ein selbstbetriebenes Raspberry-Pi-Gateway mit Fokus auf
**kontrollierte Sicherheit**, **Privacy** und **Transparenz**.

#### Kernkomponenten

* WireGuard (Remote Access)
* Pi-hole (DNS-Filter)
* Unbound (DNS-Resolver, DoT / Port 853)
* NordVPN (verpflichtender Internet-Exit)
* nftables Kill-Switch & Policy Routing

---

### Sicherheitsmodell

* Internetzugang standardmäßig **nur über VPN**
* DNS-Auflösung **nicht** beim VPN-Provider
* kein DNS-Leak, kein stiller WAN-Fallback
* klare, überprüfbare Netzwerkpfade

---

### Privacy-Eigenschaften

* ISP sieht keine Inhalte
* VPN sieht keine Domains
* DNS-Provider sieht keine echte Anschluss-IP
* keine einzelne Partei kennt alles

---

### Design-Philosophie

* keine Blackbox-Routings
* reproduzierbare Konfiguration
* minimale, robuste Architektur
* Abweichungen sofort sichtbar

**Kurz gesagt:**
Zerberus ist kein Anonymisierungsnetz, sondern ein **beherrschtes, sicheres Heim-Gateway** mit klaren Garantien.
