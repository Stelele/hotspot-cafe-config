# MikroTik Hotspot with RADIUS Authentication

A complete WiFi hotspot solution using MikroTik RouterOS with RADIUS authentication via RADIUSDesk on a Digital Ocean droplet.

## Overview

This project provides:
- **Custom Hotspot Portal** - Modified MikroTik hotspot files with voucher-based authentication
- **Server Documentation** - Setup guides for Digital Ocean droplet with WireGuard VPN and RADIUSDesk
- **Router Configuration** - WireGuard tunnel setup for secure communication between MikroTik and RADIUS server

## Project Structure

```
hotspot/
├── docs/
│   ├── server.md              # Digital Ocean droplet setup (WireGuard + RADIUSDesk)
│   └── mikrotik-vpn-setup.md  # MikroTik WireGuard peer configuration
├── hotspot/
│   ├── login.html             # Custom login page with voucher support
│   ├── alogin.html            # AJAX login handler
│   ├── rlogin.html            # RADIUS login page
│   ├── logout.html            # Logout page
│   ├── status.html            # Session status page
│   ├── redirect.html          # Redirect page
│   ├── api.json               # ChromeOS captive portal API
│   ├── md5.js                 # MD5 hashing for CHAP authentication
│   ├── css/
│   │   └── style.css          # Portal styling
│   ├── img/
│   │   ├── user.svg           # Username icon
│   │   └── password.svg       # Password icon
│   └── xml/                   # XML-based hotspot files (optional)
└── README.md                  # This file
```

## Features

### Custom Login Portal
- **Dual authentication modes**: Voucher code or username/password
- **Tabbed interface**: Easy switching between voucher and credential login
- **Voucher auto-fill**: Single input field copies to both username and password
- **Responsive design**: Works on all devices
- **CHAP support**: Secure password hashing

## Quick Start

### 1. Set Up RADIUS Server (Digital Ocean Droplet)

Follow the detailed instructions in [`docs/server.md`](docs/server.md):

1. **Install WireGuard** on Ubuntu droplet
2. **Generate keys** for VPN tunnel
3. **Configure WireGuard** interface
4. **Install RADIUSDesk** and FreeRADIUS
5. **Configure firewall** to allow RADIUS traffic
6. **Create data profiles** with bandwidth limits and time restrictions

### 2. Configure MikroTik Router

Follow the instructions in [`docs/mikrotik-vpn-setup.md`](docs/mikrotik-vpn-setup.md):

1. **Add WireGuard peer** (Ubuntu server)
2. **Assign VPN IP address** to WireGuard interface
3. **Test tunnel connectivity**
4. **Configure RADIUS client** to point to droplet
5. **Upload hotspot files** to MikroTik

### 3. Deploy Hotspot Files

Upload the contents of the `hotspot/` directory to your MikroTik router:

1. Open WinBox
2. Go to **IP** → **Hotspot**
3. Click **Files** tab
4. Upload all files from `hotspot/` folder
5. Configure hotspot server to use uploaded files

## Authentication Flow

1. User connects to WiFi hotspot
2. Captive portal redirects to `login.html`
3. User enters voucher code (or username/password)
4. Credentials sent to RADIUS server via WireGuard tunnel
5. RADIUSDesk validates against database
6. On success, user granted internet access
7. Session tracked with time/bandwidth limits

## RADIUS Profile Configuration

Create profiles in RADIUSDesk with these attributes:

| Attribute | Vendor | Check/Reply | Example Value |
|-----------|--------|-------------|---------------|
| Rd-Total-Time | RadiusDesk | check | 3600 (1 hour) |
| Rd-Reset-Type-Time | RadiusDesk | check | never |
| Rd-Cap-Type-Time | RadiusDesk | check | hard |
| Mikrotik-Rate-Limit | Mikrotik | reply | 5M/5M |

## WireGuard Network

- **Ubuntu Server**: 10.10.10.1/24
- **MikroTik Router**: 10.10.10.2/24
- **Port**: 51820

## Customization

### Branding
Edit `hotspot/login.html`:
- Change "Njeremoto Internet Cafe" to your business name
- Modify colors in `css/style.css`
- Replace logo SVG with your own

### Voucher System
The voucher tab automatically syncs the input to both username and password fields, allowing single-code authentication. Generate vouchers in RADIUSDesk with matching username/password pairs.

## Troubleshooting

### WireGuard Tunnel Issues
- Check `sudo wg show` on Ubuntu for handshake status
- Verify persistent keepalive is set to 25 seconds on MikroTik
- Ensure firewall allows UDP port 51820

### RADIUS Authentication Fails
- Verify firewall rules allow ports 1812/1813 from 10.10.10.2
- Check RADIUS client secret matches on both MikroTik and RADIUSDesk
- Review RADIUS logs: `sudo tail -f /var/log/freeradius/radius.log`

### Hotspot Not Redirecting
- Ensure hotspot files are uploaded to correct location
- Verify DNS and Walled Garden settings in MikroTik
- Check browser cache (try incognito mode)

## Requirements

- MikroTik router with RouterOS
- Digital Ocean droplet (Ubuntu 24.04 recommended)
- Domain name for SSL certificate (optional but recommended)
- WinBox for router configuration

## License

This project is provided as-is for educational and commercial use.

## Resources

- [MikroTik Hotspot Documentation](https://help.mikrotik.com/docs/display/ROS/Hotspot)
- [RADIUSDesk Documentation](https://www.radiusdesk.com/)
- [WireGuard Quick Start](https://www.wireguard.com/quickstart/)
