# Risken & Status (Schritt 1)

| Thema | Status | Hinweise/Nächste Schritte |
| --- | --- | --- |
| Stateful Start/Stop nordvpn-start/-stop | Erledigt | ip rule Handling jetzt deterministisch pro Pref via `replace_rule`/`del_pref` in `nordvpn-start.sh` und `nordvpn-stop.sh`; reduziert doppelte Regeln und Killswitch-Leakage. |
| rp_filter-Umschaltung | Erledigt | Baseline jetzt strikt 2 auf allen relevanten Interfaces, temporäre Absenkung auf 0 nur während des Connects mit garantiertem Rollback und Log-Hinweisen. Fehlerpfad bricht hart ab, falls Umschaltung scheitert. |
| NAT/Killswitch-Kombination eth0 | In Arbeit | Start-Preflight prüft ab sofort konfigurierbare WAN/LAN-Interfaces und dokumentiert nftables-Handles des Killswitch/NAT-Monitorings. Abbruch, falls Drop-Regel oder Counter fehlen. |

Nächster sinnvoller Schritt: Killswitch-Validierung weiter schärfen (z. B. Zählermonitoring automatisieren) und optionalen DNS-Fallback (Plain/zweiter DoT) nur gezielt unter Feature-Flag aktivieren.
