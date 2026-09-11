# MikroTik hAP lite - captive portal runbook

Custom login portal + RADIUSDesk via a WireGuard tunnel. RouterOS 7.22.2,
verified against the current MikroTik manual (`manual.mikrotik.com`) and the
RADIUSDesk wiki24 docs.

```
Starlink (NAT)
   │  wlan1 = WAN (DHCP client, private IP)
┌──┴────────────── MikroTik hAP lite ────────────────┐
│  identity = njeremoto-cafe-01  (=> NAS-Identifier) │
│  bridge = LAN 192.168.88.1/24 (ether2,3,4)        │
│    └─ Hotspot (hotspot1 / hsprof1) + DHCP          │
│  wg1 = 10.10.10.2/32  <--> droplet wg0 10.10.10.1  │
│  /radius  -> 10.10.10.1 (site-wide secret)         │
│  /radius incoming accept yes port=1700 (CoA/DM)    │
└─────────────────────────┬──────────────────────────┘
                          │ WireGuard :51820
┌─────────────────────────┴──────────────────────────┐
│ droplet wg0 10.10.10.1  FreeRADIUS + RADIUSDesk    │
│ RADIUS Client "njeremoto-cafe-01" type=Mikrotik    │
│ Profiles -> vouchers (user=pass) + permanent users │
└────────────────────────────────────────────────────┘
```

## Run order

Each `.rsc` is imported via WinBox → **New Terminal** (paste with Ctrl+V),
or WinBox → **Files → upload** then `/import file-name=....rsc`. Do them one
at a time; the router is a 32 MB device, so keep a terminal open and verify
between phases.

| # | File | When | Key output to capture |
|---|------|------|----------------------|
| 1 | `01-network-wan.rsc` | now | Starlink public IP (for step 2) |
| 2 | `02-wireguard.rsc` | tunnel | the **MikroTik WireGuard public key** |
| 3 | `03-hotspot-radius.rsc` | after secret | nothing - run `:put` checklist |
| 4 | portal upload + reboot | after 3 | New Arrivals appears in RADIUSDesk |

> **Plug into ether2-4 first.** WinBox management must come from the LAN side
> (192.168.88.1) - after step 1 the router is a router, not a bridge, and the
> WiFi path to Starlink becomes the WAN.

## Before you start (things to have ready)

- [ ] Laptop on ether2, connected to `192.168.88.1` via WinBox
- [ ] `/system device-mode print` → confirm HotSpot is not blocked
- [ ] Droplet public IP (run `curl -4 ifconfig.me` on the droplet)
- [ ] RADIUSDesk **site-wide shared secret**
- [ ] Timezone of the cafe (for the RADIUSDesk client entry)

## Editable values in each script

| File | Placeholder | What to put |
|------|-------------|-------------|
| `01-network-wan.rsc` | `IDENTITY` | unique router name, e.g. `njeremoto-cafe-01` |
| `02-wireguard.rsc` | `DROPLET_IP` | droplet public IP |
| `03-hotspot-radius.rsc` | `RADIUS_SECRET` | RADIUSDesk site-wide secret |
| `03-hotspot-radius.rsc` | `HS_ADMIN_PASS` | "break-glass" local hotspot password |

## After step 3: upload the custom portal

1. WinBox → **Files**: navigate into the `hotspot` folder, drag the defaults
   (`login.html`, `alogin.html`, `status.html`, `logout.html`,
   `redirect.html`, `rlogin.html`, `error.html`) to your desktop as a backup.
2. Upload the files from this repository's `mikrotik/hotspot/` into the
   router's `hotspot` folder (**Files at root → `hotspot`**). Upload the whole
   tree: `login.html`, `alogin.html`, `status.html`, `logout.html`,
   `redirect.html`, `rlogin.html`, `error.html`, `md5.js`, `api.json`,
   `favicon.ico`, `css/`, `img/`, `xml/`.
3. Reboot the router (`/system reboot`). On boot it sends Accounting-On to the
   droplet - this is what registers it under **RADIUSDesk → RADIUS Clients →
   New Arrivals**.

## The custom page flow

```
client HTTP/HTTPS
   │  unauthenticated
   v
redirect -> (link-login-only) login.html
   │  voucher tab sets username=password (single code)
   │  username/password tab = permanent users
   │  md5.js computes CHAP: hexMD5(chap-id + password + chap-challenge)
   v
POST to $(link-login-only)  ->  hotspot -> RADIUS (10.10.10.1) -> RADIUSDesk
   │
   v Access-Accept  ->  client added to hotspot hosts  ->  internet via NAT
```

`md5.js` + `api.json` (RFC 7710 client detection) are already in the folder.

## Verification (Phase 6) — AS-BUILT RESULTS 2026-09-11

| # | Check | Result |
|---|-------|--------|
| 1 | Tunnel | ✓ pings ~200ms; handshake refreshed by keepalive |
| 2 | Captive portal | ✓ HTTP → 302 to `192.168.88.1/login` |
| 3 | Custom page | ✓ "Njeremoto Internet hotspot" with voucher tab |
| 4 | Voucher login | ✓ `fullchickens` via CHAP; 3/3 RADIUS accepts |
| 5 | Time cap | ✓ live `SESSION-TIME-LEFT` countdown |
| 6 | Rate limit | ✓ dynamic queue `<hotspot-<user>>` at 10M/5M, burst 15M/8M for 5s |
| 7 | Accounting | ✓ Start/Stop rows, byte counters both directions |
| 8 | Disconnect | ✓ CoA Disconnect-ACK; `acctterminatecause=Admin-Reset` |
| 9 | Reboot | ✓ unattended recovery (link, tunnel, hotspot); Accounting-On retried until tunnel was up |
| 10 | Resources | ✓ steady-state CPU 2%, 8.8 MiB free of 32 MiB |

## Profiles + router hardening (AS-BUILT 2026-09-11)

Sizing comes from the hardware: 650 MHz single-core CPU + 32 MB RAM and
**fasttrack disabled** (required for per-user queues) put the ceiling at
~25-40 Mbps total software-NAT. 2 Mbps down / 1 Mbps up per client sustains
~7-15 concurrent streamers comfortably. One client = one device enforced via
`Simultaneous-Use := 1` (FreeRADIUS reply: "Simultaneous connections limited
to 1").

| Profile | For | Time | Data | Rate (`Mikrotik-Rate-Limit`) | Devices |
|---------|-----|------|------|------------------------------|---------|
| `1 Hour Uncapped` (id 49) | vouchers (user=pass) | 3600 s hard cap | none | `10M/5M 15M/8M 10M/5M 5/5` | `Simultaneous-Use := 1` |
| `Permanent` (id 51) | permanent users | unlimited | none | `10M/5M 15M/8M 10M/5M 5/5` | `Simultaneous-Use := 1` |

Rate attribute syntax = sustained `10M/5M`, burst `15M/8M`, burst threshold
`10M/5M`, burst time `5s` (snappier page loads inside the cap).

Router hardening applied live:

| Change | Where | Verified |
|--------|-------|----------|
| Per-device connection cap (300 sockets / IP) | `/ip firewall filter` rule 23 | ✓ 350-conn flood → 299 through, 51 dropped at the cap |
| Ad-blocking DNS for all clients | `/ip dns servers=94.140.14.14,94.140.15.15` (AdGuard) | ✓ `doubleclick.net` → `0.0.0.0`, `google.com` resolves |
| Same-rate burst profile | `radgroupreply` WISPr → `Mikrotik-Rate-Limit` | ✓ queue shows `burst-limit=15M/8M burst-time=5s/5s` |
| 1-device enforcement | `Simultaneous-Use := 1` in radgroupcheck | ✓ 2nd auth → Access-Reject |

Live test results (test voucher `easyactor`, permanent user `owner@dev`):
voucher login → dynamic queue `max-limit=10M/5M` + burst, `session-time-left`
counting down from 1 h; `owner@dev` → same queue, **no** time cap; second
concurrent login rejected with *"Simultaneous connections limited to 1"*.

## Gotchas found during the live build

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| WiFi flaps: `unicast key exchange timeout`, `deauth: authentication not valid (2)` every few seconds | wrong PSK after factory reset (2.4GHz PSK ≠ 5GHz PSK) AND `station-pseudobridge` flaps when not bridged | set correct PSK + `mode=station` |
| WG handshake OK, data dead; router sniffer shows nothing on 51820 | no auto route from peer `allowed-address` on ROS 7.22.2 | `/ip route add dst-address=10.10.10.1/32 gateway=wg1` |
| Rate limits silently ignored | defconf `fasttrack` bypasses queues | disable fasttrack rule |
| CoA NAK `Error-Cause=Unsupported-Extension` | RouterOS matches sessions by host IP | include `Framed-IP-Address` in Disconnect-Request |
| SSH/WinBox refused after hotspot enable | hotspot firewall blocks non-bypassed hosts | MAC-based `ip-binding bypassed` BEFORE enabling hotspot |
| Mgmt IP changed mid-build (.254 → .253) | DHCP server swap re-leased the laptop | bypass by MAC, not IP |
| RADIUS timeouts right after reboot | Accounting-On fired before tunnel handshook | self-heals via retries (verified) |

Rescue paths if locked out: WinBox via **MAC address** (Neighbors tab), or SSH hop droplet → `admin@10.10.10.2` through the tunnel (droplet key `root@internet-cafe-server` is installed on the router).

## Failure modes

| Symptom | Cause | Look at |
|---------|-------|---------|
| Auth fails, `bad-replies` climbs in `/radius monitor` | shared secret mismatch | `/radius print` vs RADIUSDesk site secret |
| Router never in New Arrivals | Accounting-On not reaching FreeRADIUS | `freeradius -X` on droplet, firewall UDP 1813 |
| No login-page redirect | device-mode blocks hotspot, or DNS broken | `/system device-mode print`, `/ip dns print` |
| Tunnel dead | stale peer key on droplet | run `droplet/update-wireguard-peer.sh` |
| Disconnect button fails | client type ≠ Mikrotik, or UDP 1700 blocked | `/radius incoming print`, `wg1` in LAN list |
| Starlink IP changed | nothing to do | keepalive re-homes the tunnel; verify handshake |

## Later upgrades

RADIUSDesk **central login pages**: the hotspot profile already has
`login-by=http-pap`, so you can switch to RADIUSDesk-managed pages later by
replacing the router's static hotspot files with the redirect stub from
RADIUSDesk's `rdcore` repo (`setup/mikrotik/`), adding a walled-garden IP
entry for the droplet, and enabling HTTPS on the hotspot.