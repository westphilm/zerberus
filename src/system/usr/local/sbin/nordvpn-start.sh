#!/bin/bash
set -euo pipefail

### Variablen
NVPSRV=${1:-}
LOGFILE="/var/log/nordvpn-routing.log"

# Interfaces/Netze konfigurierbar machen (Defaults bleiben wie gehabt)
LAN_IF="${LAN_IF:-eth1}"
LAN_NET="${LAN_NET:-192.168.50.0/24}"
WAN_IF="${WAN_IF:-eth0}"
WAN_NET="${WAN_NET:-192.168.1.0/24}"
VPN_IF="${VPN_IF:-nordlynx}"
WG_IF="${WG_IF:-wg0}"
WG_NET="${WG_NET:-10.6.0.0/24}"
LAN_PROBE_IP="${LAN_PROBE_IP:-192.168.50.100}"

TBL_VPN=100   # 'vpn'
TBL_WAN=200   # 'wan'

RPF_BASELINE=2
RPF_IFACES=(all default "${WAN_IF}" "${LAN_IF}")


mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
log(){ printf '%s [START] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOGFILE" ; }

log "Starte VPN Routing für ${LAN_NET} → ${VPN_IF}"


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

set_rp_filter() {
  local value="$1"
  local context="$2"
  local iface effective

  for iface in "${RPF_IFACES[@]}"; do
    if ! sysctl -w "net.ipv4.conf.${iface}.rp_filter=${value}" >/dev/null 2>&1; then
      log "Fehler: rp_filter ${iface} → ${value} (${context}) fehlgeschlagen (write)"
      return 1
    fi
    effective="$(sysctl -n "net.ipv4.conf.${iface}.rp_filter" 2>/dev/null || echo "")"
    if [[ "${effective}" != "${value}" ]]; then
      log "Fehler: rp_filter ${iface} ist ${effective}, erwartet ${value} (${context})"
      return 1
    fi
  done
}

enforce_rp_filter_baseline() {
  local iface current
  for iface in "${RPF_IFACES[@]}"; do
    current="$(sysctl -n "net.ipv4.conf.${iface}.rp_filter" 2>/dev/null || echo "")"
    if [[ "${current}" != "${RPF_BASELINE}" ]]; then
      log "Warnung: rp_filter ${iface} ist '${current:-unset}', setze auf ${RPF_BASELINE} (Baseline)"
    fi
  done

  log "rp_filter: setze Basis (${RPF_BASELINE}) auf ${RPF_IFACES[*]}"
  set_rp_filter "${RPF_BASELINE}" "baseline" || return 1
}

ip2int() {
  local IFS=.
  read -r o1 o2 o3 o4 <<<"$1"
  printf '%u' $(( (o1<<24) + (o2<<16) + (o3<<8) + o4 ))
}

cidr_contains_ip() {
  local cidr="$1" ip="$2"
  local net mask_bits mask

  net="${cidr%/*}"
  mask_bits="${cidr#*/}"

  [[ -z "${net}" || -z "${mask_bits}" ]] && return 1
  mask=$(( 0xFFFFFFFF << (32-mask_bits) & 0xFFFFFFFF ))

  local ip_int net_int
  ip_int="$(ip2int "${ip}")"
  net_int="$(ip2int "${net}")"

  [[ $((ip_int & mask)) -eq $((net_int & mask)) ]]
}

verify_wan_iface() {
  local iface="$1"
  ip link show dev "${iface}" >/dev/null 2>&1 || { log "Fehler: WAN-Interface ${iface} fehlt"; return 1; }
  local addr
  addr="$(ip -4 addr show dev "${iface}" | awk '/inet / {print $2}' | head -n1)"
  if [[ -z "${addr}" ]]; then
    log "Fehler: WAN-Interface ${iface} hat keine IPv4-Adresse"
    return 1
  fi
  if ! cidr_contains_ip "${WAN_NET}" "${addr%%/*}"; then
    log "Fehler: WAN-Interface ${iface} unerwartetes Netz (${addr}), Killswitch-Annahmen gelten nicht (soll: ${WAN_NET})"
    return 1
  fi
  if ! ip route show default | grep -q "dev ${iface}"; then
    log "Fehler: Default-Route liegt nicht auf ${iface} – Abbruch"
    return 1
  fi
}

verify_killswitch_baseline() {
  if ! nft list chain ip filter FORWARD >/dev/null 2>&1; then
    log "Fehler: nftables-Chain ip filter FORWARD nicht verfügbar – Killswitch unklar"
    return 1
  fi
  local kill_handle
  kill_handle="$(nft -a list chain ip filter FORWARD 2>/dev/null | awk '/c_drop_generic/ && /drop/ {print $NF; exit}')"
  if [[ -z "${kill_handle}" ]]; then
    log "Fehler: erwartete Killswitch-Drop-Regel fehlt (LAN/WG → ${WAN_IF})"
    return 1
  fi
  log "Killswitch-Regel (c_drop_generic) vorhanden, Handle ${kill_handle}"
  if ! nft list chain ip nat POSTROUTING >/dev/null 2>&1; then
    log "Fehler: nftables-Chain ip nat POSTROUTING nicht verfügbar – NAT-Überwachung fehlt"
    return 1
  fi
  if ! nft list chain ip nat POSTROUTING | grep -q 'c_masq_wan_public_bytes'; then
    log "Fehler: NAT-Kontrollzähler c_masq_wan_public_bytes fehlt – Kill-Switch-Monitoring unsicher"
    return 1
  fi

  local nat_handle
  nat_handle="$(nft -a list chain ip nat POSTROUTING 2>/dev/null | awk '/c_masq_wan_public_bytes/ {print $NF; exit}')"
  log "NAT-Kontrollzähler c_masq_wan_public_bytes Handle ${nat_handle:-unbekannt}"

  local wan_public_bytes
  wan_public_bytes="$(nft list counter ip nat c_masq_wan_public_bytes 2>/dev/null | awk '/bytes/ {print $NF; exit}')"
  if [[ -n "${wan_public_bytes}" && "${wan_public_bytes}" != "0" ]]; then
    log "Warnung: NAT-Kontrollzähler c_masq_wan_public_bytes bereits ${wan_public_bytes} Bytes vor Start"
  fi
}

# Robustheit direkt nach Reboot:
# warten, bis LAN eine IP hat
for i in {1..10}; do
  ip -4 addr show dev "${LAN_IF}" | grep -q 'inet ' && break
  sleep 0.5
done

verify_wan_iface "${WAN_IF}" || exit 3
verify_killswitch_baseline || exit 4

if ! enforce_rp_filter_baseline; then
  log "Abbruch: rp_filter Baseline ${RPF_BASELINE} konnte nicht gesetzt werden"
  exit 9
fi

if ! set_rp_filter 0 "pre-connect"; then
  log "Abbruch: rp_filter konnte nicht auf 0 gesetzt werden"
  exit 10
fi
log "rp_filter: temporär 0 für Verbindungsaufbau (Ifaces: ${RPF_IFACES[*]})"
trap "set_rp_filter ${RPF_BASELINE} cleanup-exit || true" EXIT

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
  WAN_IP=$(ip -4 addr show "${WAN_IF}" | awk '/inet / {print $2}' | cut -d/ -f1)
  LAN_IP=$(ip -4 addr show "${LAN_IF}" | awk '/inet / {print $2}' | cut -d/ -f1)
  # VPN-IP (nordlynx)
  VPN_IP=$(ip -4 addr show nordlynx 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
  # Öffentliche IP (über Cloudflare)
  PUBLIC_IP=$(curl -s https://1.1.1.1/cdn-cgi/trace | grep '^ip=' | cut -d= -f2)
  log "WAN-IP (${WAN_IF}): $WAN_IP"
  log "LAN-IP (${LAN_IF}): $LAN_IP"
else
  log "NordVPN disconnected"
  exit 1
fi

# Warten bis nordlynx auch routingfähig ist
for i in {1..10}; do
  ip route get 1.1.1.1 from "${LAN_PROBE_IP}" table vpn 2>/dev/null | grep -q "nordlynx" && break
  sleep 0.5
done

### 1) Alte/doppelte dynamische Regeln defensiv entfernen
ip rule del fwmark 0x520 lookup ${TBL_VPN} 2>/dev/null || true
ip rule del fwmark 0x520 lookup ${TBL_WAN} 2>/dev/null || true
ip route del table ${TBL_VPN} default 2>/dev/null || true
del_pref 1000
del_pref 95
del_pref 110

### 2) Default-Route in Tabelle 'vpn' via nordlynx setzen
ip route replace table ${TBL_VPN} default dev "${VPN_IF}"
# lokale Netze auch in table vpn bekannt machen (damit Lokalziele NICHT in den Tunnel gehen)
ip route replace table ${TBL_VPN} ${LAN_NET} dev "${LAN_IF}" scope link
ip route replace table ${TBL_VPN} ${WAN_NET} dev "${WAN_IF}" scope link
ip route replace table ${TBL_VPN} ${WG_NET}  dev "${WG_IF}"   scope link 2>/dev/null || true
# (optional, falls nicht ohnehin da)
ip route replace table ${TBL_VPN} 10.5.0.0/16     dev "${VPN_IF}" scope link 2>/dev/null || true

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
log "rp_filter: stelle Baseline ${RPF_BASELINE} nach Setup wieder her"
if ! set_rp_filter "${RPF_BASELINE}" "post-setup"; then
  log "Abbruch: rp_filter konnte nicht auf ${RPF_BASELINE} zurückgestellt werden"
  exit 11
fi
trap - EXIT
sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "OK: NordVPN dynamische Regeln aktiv (LAN via vpn, fwmark 0x520 → vpn)."

snapshot "VPN Connection established"
# Teste Dummy-Traffic durchleiten
curl -s --interface nordlynx https://ifconfig.me || log "Fehler: curl nordlynx geht nicht"
log "Log: $LOGFILE"
log "Ready: LAN ${LAN_NET} routes via NordVPN to $PUBLIC_IP"

exit 0
