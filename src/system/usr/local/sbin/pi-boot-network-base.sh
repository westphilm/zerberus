#!/system.usr/bin/env bash
# pi-boot-network-base.sh
# Dauerhafte Grundregeln für Pi als Gateway + spätere NordVPN-Nutzung.

set -u

### Variablen
LAN_IF="eth1"
WAN_IF="eth0"
VPN_IF="nordlynx"          # Interface-Name vom NordVPN WireGuard-Adapter
WG_IF="wg0"                # Dein mobiles WireGuard-Interface (falls genutzt)

LAN_NET="192.168.50.0/24"
WAN_GW="192.168.1.1"
WAN_IP="192.168.1.2"
WG_NET="10.6.0.0/24"

TBL_VPN=100
TBL_WAN=200
# DoT wird nicht mehr verwendet
# TBL_NOVPN=300

# löscht ALLE Regeln mit der angegebenen Pref (falls mehrere vorhanden sind)
del_pref() {
  local p="$1"
  # solange eine Regel mit pref p existiert, löschen
  while ip -4 rule show | grep -qE "^[[:space:]]*$p:"; do
    ip -4 rule del pref "$p" 2>/dev/null || break
  done
}

echo "[BOOT] Starte dauerhaftes Basis-Netzsetup …"

### 1) Routingtabellen (WAN/NOVPN) & Basisrouten
ip route replace table ${TBL_WAN}  default via ${WAN_GW} dev ${WAN_IF} src ${WAN_IP}
ip route replace table ${TBL_VPN}  ${LAN_NET} dev ${LAN_IF}
ip route replace table ${TBL_VPN}  192.168.1.0/24 dev ${WAN_IF}
# DoT wird nicht mehr verwendet
# ip route replace table ${TBL_NOVPN} default via ${WAN_GW} dev ${WAN_IF} src ${WAN_IP}


### 2) Statische Policy-Rules (dauerhaft)
# WireGuard-Bypass immer über WAN
#ip rule add fwmark 0x77  lookup ${TBL_WAN}  priority 45    2>/dev/null || true
# Zielbasierte Ausnahme: eigenes WG-Subnetz bleibt im main
#ip rule add to ${WG_NET} lookup main priority 90           2>/dev/null || true
# DoT/Bypass (novpn) dauerhaft
#ip rule add fwmark 0x355 lookup ${TBL_NOVPN} priority 100  2>/dev/null || true

# Statische Policy-Rules (dauerhaft, kollisionsfest)
del_pref 45
ip -4 rule add fwmark 0x77 lookup main priority 45

del_pref 90
ip -4 rule add to ${WG_NET} lookup main         priority 90

# DoT wird nicht mehr verwendet
del_pref 100
# ip -4 rule add fwmark 0x355 lookup ${TBL_NOVPN} priority 100


###############################################################################
# 3) nftables Grundgerüst (FORWARD + NAT + MSS) in /system.etc/nftables.conf
###############################################################################

### 4) sysctl
#net.ipv4.ip_forward=1
#net.ipv4.conf.all.rp_filter=2
#net.ipv4.conf.default.rp_filter=2
#net.ipv4.conf.eth1.rp_filter=2
# danach: sudo sysctl --system

echo "[BOOT] Basis-Netzsetup fertig"
