# Configuring Droplet server

## 1. VPN Tunnel (Wireguard)

Commands to execute.

Install wireguard

```bash
sudo apt install wireguard
```

Execute Instructions

Generate Public and Private keys to be used when linking with mikrotik router
```bash
mkdir mikrotik-router
cd mikrotik-router
umask 077
wg genkey > privatekey
wg pubkey < privatekey > publickey
```

Create config file for wireguare on droplet

```bash
vim /etc/wireguard/wg0.conf
```

Add the following details
```ini
[Interface]
PrivateKey = <PASTE_UBUNTU_PRIVATE_KEY_HERE>
Address = 10.10.10.1/24
ListenPort = 51820

[Peer]
PublicKey = <PASTE_MIKROTIK_PUBLIC_KEY_HERE>
# The AllowedIPs specifies what traffic can go through this tunnel. 
# 10.10.10.2/32 means just the MikroTik itself. 
AllowedIPs = 10.10.10.2/32
# Replace with your MikroTik's public IP or hostname and WireGuard port
```

Start up tunnel connection 
```bash
# Start the tunnel
sudo wg-quick up wg0

# Enable it to start automatically when the server reboots
sudo systemctl enable wg-quick@wg0
```

Set things up on the Mikrotik side also as shown by this [Mikrotik Router Setup VPN Peer](mikrotik-vpn-setup.md)

## 2. RadiusDesk

Follow the installation instructions at 
1. https://www.radiusdesk.com/wiki24/install_24_4
2. https://www.radiusdesk.com/wiki24/install_24_4_freeradius
3. https://www.radiusdesk.com/wiki24/install_tweak


### Note for applying patches in step 1
You can run this to apply all the patches

```bash
cd /var/www/rdcore/cake4/rd_cake/setup/db/
for patch in 8.*; do
    echo "Applying $patch..."
    sudo mysql -u root rd < "$patch"
done
```

### Configuring firewall

Assuming you've set a nice domain and used certbot for the ssl certificate, you need to add the following to allow the firewall to accept auth traffic from the mikrotik router

```bash
sudo ufw allow from 10.10.10.2 to any port 1812 proto udp
sudo ufw allow from 10.10.10.2 to any port 1813 proto udp
```

This assumes the ip you assigned your mikrotik router in the vpn tunnel is 10.10.10.2. If not, replace with what you used


### Data profiles

Create a RADIUS profile and make sure to add the following properties to the created profile

| Attribute | Vendor | Check/Reply | Value |
| --- | --- | --- | --- |
| Rd-Total-Time | RadiusDesk | check | 3600 |
| Rd-Reset-Type-Time | RadiusDesk | check | never |
| Rd-Cap-Type-Time | RadiusDesk | check | hard |
| Mikrotik-Rate-Limit | Mikrotik | reply | 5M/5M |