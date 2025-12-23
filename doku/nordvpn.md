# NordVPN

## Policy-Routing Steuerung
- `nordvpn-start.sh` ersetzt ip rule Einträge jetzt deterministisch per Priority, um doppelte Regeln und inkonsistente Zustände zu vermeiden.
- `nordvpn-stop.sh` nutzt dieselbe Logik für den Rückbau (fwmark- und source-basierte Regeln) und stellt den WAN-Baseline-Zustand zuverlässig wieder her.

Diese Idempotenz reduziert Risiken im Start/Stop-Pfad (Killswitch-Leakage, fehlende Cleanup-Schritte) und gilt als abgeschlossen für Schritt 1.
