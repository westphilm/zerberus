# DNS-Auflösung über VPN – Vergleich der Varianten

## Kontext

Im aktuellen Setup läuft DNS wie folgt:

Client → WireGuard → Pi-hole → Unbound → NordVPN-Tunnel → externe DNS-Resolver (DoT/853) → NordVPN-Tunnel → Unbound → Pi-hole → Client

Verglichen werden zwei Varianten:

* **Variante A (aktuell):** DNS über VPN zu **explizit konfigurierten externen DNS-Providern** (DoT)
* **Variante B:** DNS-Auflösung **vollständig dem VPN-Provider überlassen**

---

## Vergleich: Sichtbarkeit von Informationen

| **Was / Wer sieht was**                   | **Internet-Provider (ISP)**         | **NordVPN**                        | **Externer DNS-Provider** |
|-------------------------------------------|-------------------------------------|------------------------------------| ------------------------- |
| **Echte öffentliche IP**                  | ja                                  | ja                                 | nein                      |
| **VPN-IP (Exit-IP)**                      | nein                                | ja                                 | ja                        |
| **DNS-Ziel-IP (1.1.1.1 etc.)**            | nein                                | ja                                 | ja                        |
| **Aufgerufene Domains (Klartext)**        | nein                                | nein                               | ja                        |
| **DNS-Anfragen-Inhalt (verschlüsselt)**   | nein (verschlüsselt, Port 853 + VPN) | nein (verschlüsselt, Port 853)     | nein                      |
| **Nutzdaten (HTTPS/TLS)**                 | nein (verschlüsselte TLS-Metadaten) | nein (verschlüsselte TLS-Metadaten) | nein                      |
| **Zeitpunkt / Frequenz von DNS-Anfragen** | nein                                | ja                                 | ja                        |
| **Zuordnung DNS → echter Anschluss**      | ja (indirekt, Traffic-Metadaten)    | ja                                 | nein                      |
| **Geräte/Clients im LAN**                 | nein                                | nein                               | nein                      |

---

## Variante A – DNS über VPN zu externen DNS-Providern (Status quo)

### Vorteile

* Volle **Kontrolle über Resolver-Auswahl** (Cloudflare, Quad9, etc.)
* **DoT-Ende-zu-Ende** zwischen Unbound und Resolver
* VPN-Provider sieht **keine Domains**, nur verschlüsselten DNS-Traffic
* DNS-Provider sieht **keine echte IP**, nur VPN-Exit
* Unabhängig vom VPN-Anbieter (Portabilität)
* Kombination mit lokalen Overrides, Caching, Hardening möglich

### Nachteile

* Zwei Parteien involviert (VPN + DNS-Provider)
* DNS-Provider sieht **alle aufgelösten Domains**
* Metadaten-Korrelation theoretisch möglich (Zeit/Frequenz)

---

## Variante B – DNS vollständig dem VPN-Provider überlassen

### Vorteile

* Einfachere Architektur
* Nur **ein externer Akteur** (VPN)
* Keine separate DoT-Konfiguration notwendig
* Geringfügig weniger Latenz

### Nachteile

* **VPN sieht sowohl IP als auch Domains** → vollständiges Nutzungsprofil möglich
* Keine Transparenz über verwendete Resolver
* Keine eigenen DNS-Policies, Overrides oder Filter möglich
* Vertrauen vollständig auf VPN-Provider konzentriert

---

## Datenschutz-Bewertung (Kurzfassung)

| Aspekt                              | Variante A | Variante B |
| ----------------------------------- | ---------- | ---------- |
| **Datenminimierung**                | sehr gut   | mittel     |
| **Trust-Verteilung**                | verteilt   | zentral    |
| **Technische Kontrolle**            | hoch       | gering     |
| **Missbrauchsresistenz**            | hoch       | geringer   |
| **Forensische Nachvollziehbarkeit** | gering     | höher      |

---

## Sicherheitsrelevante Zusatzaspekte

* **DoT verhindert DNS-Manipulation** durch VPN-Exit oder Transit-Netze
* **Split-Knowledge-Prinzip:** kein einzelner Akteur kennt *IP + Domain*
* **WG-only-Zugriff** verhindert DNS-Missbrauch von außen
* **Zentraler Audit-Punkt:** Pi-hole + Unbound erlauben vollständige lokale Analyse

---

## Fazit

Die aktuelle Variante (**DNS über VPN zu eigenen Resolvern**) ist:

* datenschutzfreundlicher
* transparenter
* technisch robuster
* besser kontrollierbar

Sie entspricht einem **"best achievable"-Setup**, solange man VPN nutzt, aber dennoch Kontrolle behalten möchte.
