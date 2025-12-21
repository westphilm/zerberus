# Pi hole

Enthält die Pi-hole Konfigurationsdatei für das Unbound-Plugin (DNS).    

- `/etc/unbound/unbound.conf.d/pi-hole.md`

**:i:** 
- **kaskadierende Anfragen** an autoritative Root-Server auf `Port #853 (forward-tls-upstream: yes)` nicht möglich
- deshalb `forward-zone` zu DNS-Servern mit explizitem DoT (853) Support
