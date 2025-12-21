#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/nordvpn-routing.log"
LAN_NET="192.168.50.0/24"
WG_NET="10.6.0.0/24"
TBL_VPN=100
TBL_WAN=200

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
log(){ printf '%s [STOP ] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOGFILE" ; }


snapshot() {
  # show all rules: sudo nft list ruleset
  echo " "
  echo "=== $1 ==="
  echo "-- IP rule --"; ip -o -4 rule
  echo "-- Main route --"; ip route show table main
  echo "-- VPN route (100) --"; ip route show table 100 2>/dev/null || true
  echo "-- INPUT --"; nft list chain ip filter INPUT | tee -a "$LOGFILE"
  echo "-- FORWARD --"; nft list chain ip filter FORWARD | tee -a "$LOGFILE"
  echo "-- NAT POSTROUTING --"; nft list chain ip nat POSTROUTING | tee -a "$LOGFILE"
  echo
}

###################
# Dynamische Rules entfernen:
#

# 1) Dynamische fwmark-Umschaltung zurückdrehen
# defensiv: falls schon eine 110er Rule existiert, einmal löschen
ip rule del fwmark 0x520 lookup ${TBL_VPN} 2>/dev/null || true
ip -4 rule del pref 110 2>/dev/null || true
ip rule add fwmark 0x520 lookup ${TBL_WAN} priority 110 2>/dev/null || true

# 2) Source-Policy für LAN via vpn entfernen (falls sie gesetzt wurde)
# (Je nach Startscript-Formulierung beides versuchen:)
ip rule del from ${LAN_NET} lookup ${TBL_VPN} 2>/dev/null || true
ip rule del pref 1000 from ${LAN_NET} lookup ${TBL_VPN} 2>/dev/null || true

# Policy WG - VPN
ip rule del from ${WG_NET} lookup ${TBL_VPN} 2>/dev/null || true
ip rule del pref 95 from ${WG_NET} lookup ${TBL_VPN} 2>/dev/null || true

# 3) vpn-Defaultroute entfernen (optional defensiv)
ip route del table ${TBL_VPN} default 2>/dev/null || true

echo "NordVPN dynamische Regeln zurückgesetzt."

####################################################################################

log "Stoppe Routing über NordVPN und trenne VPN"

# 1) VPN verbunden?
if sudo -n /usr/bin/nordvpn status | grep -qi 'Status: Connected'; then
  log "NordVPN disconnecting ..."

  # 1a) VPN trennen (idempotent)
  if sudo /usr/bin/nordvpn status | grep -qi 'Status: Connected'; then
    sudo /usr/bin/nordvpn disconnect || true
    log "NordVPN disconnected"
  else
    log "NordVPN not connected"
  fi

  PUBLIC_IP=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
  log "Public IP: $PUBLIC_IP"

  # LAN-IP (eth0)
  LAN_IP=$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)


  # Öffentliche IP (über Cloudflare)
  PUBLIC_IP=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
  log "PUBLIC-IP: $PUBLIC_IP"
  log "LAN-IP: $LAN_IP"

else
  log "NordVPN already disconnected"
  # exit 0
fi

snapshot "Finish"

log "Ready: 192.168.50.0/24 geht direkt über WAN (if permitted)."
log "Logfile: /var/log/nordvpn-routing.log"

