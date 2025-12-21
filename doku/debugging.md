
# Analyzing & Debugging 

## Network

### Wireguard (Pi Gateway)

#### WG Live Status
```
 ### wg0 live connection status
 $ sudo watch -n 1 'wg show wg0'
```

#### WG Configuration
```
 ### ...
 $ systemctl status wg0.service
 $ sudo nano /etc/wireguard/wg0.conf
```

#### Routing
- siehe: [fmark_routing.md](fmark-routing.md)


### NFTables
#### Pi Gateway