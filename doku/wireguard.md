# Wireguard Service

## Konfiguration 

### Secrets ablegen

Secrets sind der eigene **Private Key** sowie die **Public Keys** erlaubter Clients. 
Diese dürfen **nicht versioniert** werden, sondern in der Systemd-Konfiguration referenziert.

Die Hinterlegung der Secrets auf dem Zielsystem muss adminstritiv mit Root-Rechten erfolgen.
Systemd liest diese aus beim Servicestart und im ExecStart an Wireguard übergeben.

#### Initiale Erstellung der Wireguard-Secrets auf dem Pi Gateway 
`nicht versionieren`
```bash 
  $ sudo install -d -m 700 /etc/zerberus/credentials
  $ sudo install -m 600 /dev/null /etc/zerberus/credentials/wg0_privatekey
  $ sudo install -m 600 /dev/null /etc/zerberus/credentials/wg0_peer_publickey
```

Inhalte:
- /etc/zerberus/credentials/wg0_privatekey → nur der PrivateKey (eine Zeile)
- /etc/zerberus/credentials/wg0_peer_publickey → nur der Peer PublicKey (eine Zeile)

#### Inbetriebnahme
Zunächst muss der Standard-Service-Starter `wg-quick@wg0` **deaktiviert** werden.
Damit wird auch die Konfigurationsdatei `/etc/wireguard/wg0.conf` **obsolete**.
```bash
  $ sudo systemctl status wg-quick@wg0
  $ sudo systemctl disable --now wg-quick@wg0
  $ sudo mv /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak
```

Die Wireguard Service wird über die Unitdatei `/etc/systemd/system/wg0.service` gesteuert, 
die auch alle erforderlichen Environment-Variablen bereitstellt und in ExecStart an den Wireguard-Daemon übergibt.

```bash
  $ sudo systemctl daemon-reload
  $ sudo systemctl enable --now wg0
  $ sudo systemctl status wg0
```

Aufrufparameter bei Servicestart sehen 
```bash
  $ sudo systemctl show wg0 ExecStart
```
