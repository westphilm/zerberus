# Risken & Status (Schritt 1)

| Thema | Status | Hinweise/Nächste Schritte |
| --- | --- | --- |
| Stateful Start/Stop nordvpn-start/-stop | Erledigt | ip rule Handling jetzt deterministisch pro Pref via `replace_rule`/`del_pref` in `nordvpn-start.sh` und `nordvpn-stop.sh`; reduziert doppelte Regeln und Killswitch-Leakage. |
| rp_filter-Umschaltung | Offen | Start-Skript setzt `rp_filter` vor dem Connect auf 0 und stellt nach Policy-Setup auf 2 zurück. Zur Absicherung Pending: explizite Verifikation des Rücksetzens (z. B. mittels Status-Check/Log) und Fail-Stop, falls Umschalten nicht gelingt. |
| NAT/Killswitch-Kombination eth0 | Offen | Killswitch/NAT-Annahmen basieren auf eth0 als WAN. ToDo: Validierung/Logging der Interface-Annahmen beim Start und klares Abbruch-/Fallback-Verhalten, falls eth0 nicht WAN ist. |

Nächster sinnvoller Schritt: rp_filter-Umschaltung absichern (Status-Check + Fehlerpfad), danach die eth0-Killswitch-Annahmen überprüfen und dokumentieren.
