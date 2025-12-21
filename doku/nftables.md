# NFTables


## eth1, wg0 => WAN Killswitch  

`/etc/nftables.conf`
```bash
### Kill-Switch: LAN/WG darf nicht ins Internet über eth0 (außer 192.168.1.0/24)  
  $ iifname { "eth1", "wg0" } oifname "eth0" ip daddr != 192.168.1.0/24 counter name c_drop_generic drop
```

**Droppt jeden Traffic** aus dem 50er Netz, der *nicht über VPN* geht.

- LAN-Clients und WG-Clients müssen über VPN
- Direktes Internet über WAN ist gesperrt
- Interne Kommunikation im 1er-Netz bleibt erlaubt

### Deaktivieren des Killswitches

`/etc/nftables.conf`
```bash 
  # $ iifname { "eth1", "wg0" } oifname "eth0" ip daddr != 192.168.1.0/24 counter name c_drop_generic drop
```
 danach:

```bash 
  $ sudo nft -f /etc/nftables.conf
  $ sudo systemctl reload nftables
```
