#!/bin/bash
set -euo pipefail

### Variablen
NVPSRV=${1:-}
LOGFILE="/var/log/nordvpn-routing.log"
LAN_IF="eth1"
VPN_IF="nordlynx"
LAN_NET="192.168.50.0/24"
WG_NET="10.6.0.0/24"

TBL_VPN=100   # 'vpn'
TBL_WAN=200   # 'wan'


mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
log(){ printf '%s [START] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOGFILE" ; }

log "Starte VPN Routing für 192.168.50.0/24 → nordlynx"


snapshot() {
  # show all rules: sudo nft list ruleset
  echo " "
  echo "=== $1 ==="
  echo "-- IP rule --"; ip -o -4 rule
  echo "-- Main route --"; ip route show table main
  echo "-- VPN route (100) --"; ip route show table 100 2>/dev/null || true
  #echo "-- INPUT --"; nft list chain ip filter INPUT | tee -a "$LOGFILE"
  #echo "-- FORWARD --"; nft list chain ip filter FORWARD | tee -a "$LOGFILE"
  #echo "-- NAT POSTROUTING --"; nft list chain ip nat POSTROUTING | tee -a "$LOGFILE"
  echo "-- MANGLE FORWARD --"; nft list chain ip tune fwd_mss | tee -a "$LOGFILE"
  echo "-- INPUT --";   nft list chain ip filter INPUT   2>/dev/null || echo "(ip filter INPUT fehlt)"
  echo "-- FORWARD --"; nft list chain ip filter FORWARD 2>/dev/null || echo "(ip filter FORWARD fehlt)"
  echo "-- NAT POSTROUTING --"; nft list chain ip nat POSTROUTING 2>/dev/null || iptables-nft -t nat -S POSTROUTING
  echo
}

# löscht ALLE Regeln mit der angegebenen Pref (falls mehrere vorhanden sind)
del_pref() {
  local p="$1"
  # solange eine Regel mit pref p existiert, löschen
  while ip -4 rule show | grep -qE "^[[:space:]]*$p:"; do
    ip -4 rule del pref "$p" 2>/dev/null || break
  done
}

replace_rule() {
  # Idempotent ersetzen (oder setzen) einer Regel mit fixer Priorität
  # Beispiel: replace_rule 1000 from ${LAN_NET} lookup ${TBL_VPN}
  local pref="$1"
  shift
  del_pref "$pref"
  ip -4 rule add pref "$pref" "$@" 2>/dev/null || true
}

# Robustheit direkt nach Reboot:
# warten, bis eth1 eine IP hat
for i in {1..10}; do
  ip -4 addr show dev eth1 | grep -q 'inet ' && break
  sleep 0.5
done

# kurz vor dem Connect: rp_filter lockern (Handshake-sicher)
sysctl -w net.ipv4.conf.all.rp_filter=0  >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.eth0.rp_filter=0 >/dev/null
sysctl -w net.ipv4.conf.eth1.rp_filter=0 >/dev/null

# 1) VPN verbunden?
if sudo -n /usr/bin/nordvpn status | grep -qi 'Status: Connected'; then
  log "NordVPN is running"
else
  log "Verbindung wird hergestellt"

  if [[ -n "$NVPSRV" ]]; then
      if [[ "$NVPSRV" == "auto" ]]; then
          log "Connect to: auto (Germany)"
          sudo -n /usr/bin/nordvpn connect
      else
          log "Connect to: $NVPSRV"
          sudo -n /usr/bin/nordvpn connect "$NVPSRV"
      fi
  else
      log "Connect to: empty (Germany)"
      sudo -n /usr/bin/nordvpn connect
  fi

  # kurz warten, bis nordlynx steht
  for i in {1..10}; do
    ip -4 addr show dev nordlynx 2>/dev/null | grep -q 'inet ' && break
    sleep 0.5
  done
fi

if sudo -n /usr/bin/nordvpn status | grep -qi 'Status: Connected'; then
  log "NordVPN connected"
  PUBLIC_IP=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
  log "PUBLIC-IP: $PUBLIC_IP"
  VPN_IP=$(ip -4 addr show nordlynx | awk '/inet / {print $2}' | cut -d/ -f1)
  log "VPN-IP: $VPN_IP"
  # LAN-IP (eth0)
  LAN_IP=$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  # VPN-IP (nordlynx)
  VPN_IP=$(ip -4 addr show nordlynx 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
  # Öffentliche IP (über Cloudflare)
  PUBLIC_IP=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
  log "LAN-IP: $LAN_IP"
else
  log "NordVPN disconnected"
  exit 1
fi

# Warten bis nordlynx auch routingfähig ist
for i in {1..10}; do
  ip route get 1.1.1.1 from 192.168.50.100 table vpn 2>/dev/null | grep -q "nordlynx" && break
  sleep 0.5
done

#############################
# --- Nach "NordVPN connected" / sobald nordlynx up ist, einfügen ---
#
ensure_nat_for_vpn() {
  # Subnetze, die via nordlynx NAT brauchen
  local nets=("192.168.1.0/24" "192.168.50.0/24")

}

##
########################

# Finale Prüfung des VPN-Interfaces bevor weiter
ip link show dev nordlynx >/dev/null 2>&1 || {
  log "Fehler: nordlynx-Interface nicht aktiv – Verbindung fehlgeschlagen"
  exit 2
}


###########################################################################################
# Neuer Stand nach Refactoring:
#########################################################

# Neue Testvarianten, erstmal auskommentiert, evtl noch übernehmen:
#
### 0) Preflight: ist NordVPN (nordlynx) da?
#if ! ip link show "${VPN_IF}" >/dev/null 2>&1; then
#  echo "Fehler: Interface ${VPN_IF} nicht vorhanden (NordVPN nicht verbunden?). Abbruch." >&2
#  exit 1
#fi

# kurze Warte-Schleife bis IPv4 konfiguriert ist (falls Connect gerade erst passiert ist)
#for i in {1..20}; do
#  if ip -4 addr show dev "${VPN_IF}" | grep -q 'inet '; then break; fi
#  sleep 0.2
#done

### 1) Alte/doppelte dynamische Regeln defensiv entfernen
ip rule del fwmark 0x520 lookup ${TBL_VPN} 2>/dev/null || true
ip rule del fwmark 0x520 lookup ${TBL_WAN} 2>/dev/null || true
ip route del table ${TBL_VPN} default 2>/dev/null || true
del_pref 1000
del_pref 95
del_pref 110

### 2) Default-Route in Tabelle 'vpn' via nordlynx setzen
ip route replace table ${TBL_VPN} default dev "${VPN_IF}"
##########
 # lokale Netze auch in table vpn bekannt machen (damit Lokalziele NICHT in den Tunnel gehen)
 ip route replace table ${TBL_VPN} 192.168.50.0/24 dev "${LAN_IF}" scope link
 ip route replace table ${TBL_VPN} 192.168.1.0/24  dev eth0        scope link
 ip route replace table ${TBL_VPN} 10.6.0.0/24     dev wg0         scope link 2>/dev/null || true
 # (optional, falls nicht ohnehin da)
 ip route replace table ${TBL_VPN} 10.5.0.0/16     dev "${VPN_IF}" scope link 2>/dev/null || true
###
##########

# LAN → vpn
replace_rule 1000 from ${LAN_NET} lookup ${TBL_VPN}

# Leitet sämtlichen Traffic vom WireGuard-Clientnetz standardmäßig in die VPN-Routingtabelle.
# Erzwingt: WG-Clients → Internet über VPN.
# Ausnahmen (LAN / lokale Netze) werden innerhalb der VPN-Tabelle über explizite Routen geregelt.
replace_rule 95 from ${WG_NET} lookup ${TBL_VPN}

# Leitet allen Traffic mit fwmark 0x520 in die VPN-Routingtabelle.
# Dieses Mark kennzeichnet VPN-Nutzdaten (z. B. von LAN-Clients), die gezielt über nordlynx geroutet werden sollen.
# Ermöglicht saubere Trennung zwischen VPN-Payload und nicht-VPN-Traffic auf Routing-Ebene.
replace_rule 110 fwmark 0x520 lookup ${TBL_VPN}

### 5)
# nach erfolgreichem Connect + Regeln:
sysctl -w net.ipv4.conf.all.rp_filter=2       >/dev/null
sysctl -w net.ipv4.conf.default.rp_filter=2   >/dev/null
sysctl -w net.ipv4.conf.eth0.rp_filter=2      >/dev/null
sysctl -w net.ipv4.conf.eth1.rp_filter=2      >/dev/null
sysctl -w net.ipv4.ip_forward=1               >/dev/null

echo "OK: NordVPN dynamische Regeln aktiv (LAN via vpn, fwmark 0x520 → vpn)."

snapshot "VPN Connection established"
# Teste Dummy-Traffic durchleiten
curl -s --interface nordlynx https://ifconfig.me || log "Fehler: curl nordlynx geht nicht"
log "Log: $LOGFILE"
log "Ready: LAN 192.168.50.0/24 routes via NordVPN to $PUBLIC_IP"

exit 0
