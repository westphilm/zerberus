# Netzwerkübersicht (Topologie)

```mermaid
graph TD
    Fritz["Fritzbox<br/>192.168.1.1 (WAN)"]
    Pi["Raspberry Pi 5<br/>192.168.1.2 (WAN)<br/>192.168.50.1 (LAN)"]
    LAN["LAN 192.168.50.0/24"]
    PC["PC<br/>192.168.50.x"]
    Phone["Phone (WireGuard)<br/>10.6.0.x"]
    PiHole["Pi-hole + Unbound"]
    NordVPN["NordVPN (nordlynx)<br/>10.5.0.2"]

    Fritz -->|eth0| Pi
    Pi -->|eth1| LAN
    LAN --> PC
    Phone -->|WireGuard| Pi
    Pi -->|DNS| PiHole
    Pi -->|Tunnel| NordVPN
