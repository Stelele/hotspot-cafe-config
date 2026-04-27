# RADIUS + Captive Portal Setup Guide

## Architecture

```
Cudy Router <--RADIUS (1812/1813)--> FreeRADIUS (daloradius container)
                                        |
                                        v
                                   MariaDB (radius-db)
                                        ^
                                        |
                              daloRADIUS Web UI (port 8082)
```

## Deployment

```bash
# Build and start all services
docker compose up -d --build

# Check that FreeRADIUS is running
docker exec daloradius freeradius -C
# Expected: "Configuration appears to be OK"

# Check that port 1812 is listening
docker exec daloradius netstat -ulnp | grep 1812
# Expected: udp  0  0 0.0.0.0:1812  0.0.0.0:*  PID/freeradius
```

## Register Cudy Router as NAS Client

1. Log in to daloRADIUS at `http://<your-server>:8082` (default: `administrator` / `radius`)
2. Navigate to **Management > NAS**
3. Click **New NAS**
4. Fill in:
   - **NAS IP Address**: Your Cudy router's IP address (the IP FreeRADIUS will see, typically the router's WAN IP or the WireGuard IP if tunneling)
   - **NAS Type**: `other`
   - **Secret**: The shared secret you configured in `RADIUS_SECRET` (e.g., `testing123` or your custom secret)
   - **Shortname**: `cudy-router`
   - **Description**: `Cudy Router for captive portal`
5. Click **Apply**

## Configure Cudy Router

In your Cudy router web interface:

1. Go to **Captive Portal** settings
2. Enable Captive Portal
3. Set RADIUS server to your droplet IP: `<DROPLET_IP>`
4. Set RADIUS port: `1812`
5. Set RADIUS secret: Same value as `RADIUS_SECRET`
6. Save and apply

## Testing

Test RADIUS authentication from the container:
```bash
docker exec daloradius radtest <username> <password> localhost 0 testing123
```

Expected response: `Access-Accept`

## Troubleshooting

### FreeRADIUS not starting
```bash
docker logs daloradius
docker exec daloradius freeradius -X  # Debug mode
```

### RADIUS requests not reaching server
```bash
# Check if port is open from host
nc -vu <DROPLET_IP> 1812

# Check firewall rules
sudo ufw status
# Ensure UDP 1812 and 1813 are allowed
```

### Database connection issues
```bash
docker exec daloradius mysqladmin ping -hradius-db -uradius -p<RADIUS_DB_PASSWORD>
```

### View FreeRADIUS logs
```bash
docker exec daloradius tail -f /var/log/freeradius/radius.log
```
