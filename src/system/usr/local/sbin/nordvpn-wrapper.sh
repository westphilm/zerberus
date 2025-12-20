#!/system.usr/bin/env bash
set -euo pipefail

# → HIER deine bestehenden Skripte eintragen:
POST_UP="/usr/local/sbin/nordvpn-start.sh"
POST_DOWN="/usr/local/sbin/nordvpn-stop.sh"

ACTION="${1:-start}"
# shift || true  # Rest-Args in "$@"
NVPSRV="${2:-}"

# Aus Environment-Datei (optional): VPN_ARGS='--group p2p --protocol nordlynx'
# VPN_ARGS="${VPN_ARGS:-}"

echo "Optional ARGs: $NVPSRV"

case "$ACTION" in
  start)
    echo "[wrapper] connect $NVPSRV"
    #sudo nordvpn connect $VPN_ARGS "$@"
    # kleines Delay, bis nordlynx-IF steht:
    sleep 2
    if [[ -x "$POST_UP" ]]; then "$POST_UP" "$NVPSRV"; fi
    ;;
  stop)
    echo "[wrapper] disconnect"
    #sudo nordvpn disconnect || true
    if [[ -x "$POST_DOWN" ]]; then "$POST_DOWN" || true; fi
    ;;
  restart)
    echo "[wrapper] restarting ..."
    #sudo nordvpn disconnect || true
    #sleep 2
    if [[ -x "$POST_DOWN" ]]; then "$POST_DOWN" || true; fi
    sleep 3
    #echo "[wrapper] nordvpn connect $NVPSRV"
    #sudo nordvpn connect $VPN_ARGS "$NVPSRV"
    # kleines Delay, bis nordlynx-IF steht:
    #sleep 2
    if [[ -x "$POST_UP" ]]; then "$POST_UP" "$NVPSRV"; fi
    ;;
  status)
    echo "[wrapper] restarting ..."
    sudo nordvpn status
    sudo curl -s https://ifconfig.io
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status} [nordvpn-args...]"
    exit 1
    ;;
esac
