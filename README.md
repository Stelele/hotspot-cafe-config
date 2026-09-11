# Hotspot Cafe Config — Complete Build & Deployment Reference

Captive-portal WiFi hotspot for **Njeremoto Internet Cafe**: a MikroTik hAP lite
runs the portal; RADIUSDesk + FreeRADIUS on a DigitalOcean droplet authenticate
vouchers and permanent users over a WireGuard tunnel.

> **Status: DEPLOYED & VERIFIED 2026-09-11.**

> ## ⚠️ NOTE — values redacted
>
> This repository has a **public** remote: `https://github.com/Stelele/hotspot-cafe-config`.
> All passwords, PSKs, keys and the RADIUS site secret are **redacted** in the
> docs (and placeholders in the scripts), so nothing sensitive is committed.
> The real values live on the systems themselves — see "Where the real values
> live" in §3.

---

## 1. What this is

```
Starlink (NAT)
   │
┌──┴───────── Cudy router (192.168.1.1) ─────────┐
│   SSID "Cudy-Outdoor" 2.4GHz (ch 11)          │
│   SSID (5GHz, different PSK)                   │
└───────────────┬────────────────────────────────┘
                │ wlan1 = WAN station (2.4GHz, DHCP 192.168.1.137)
        ┌───────┴──────────────── MikroTik hAP lite ──────────────────┐
        │  identity = njeremoto-cafe-01                                │
        │  bridge = LAN 192.168.88.1/24 (ether2,3,4)                  │
        │    └─ Hotspot (hotspot1 / hsprof1) + DHCP pool .2-.254      │
        │  wg1 = 10.10.10.2/32  <── WireGuard ──>  droplet wg0        │
        │  /radius -> 10.10.10.1 (RADIUSDesk site secret)             │
        │  /radius incoming accept port=1700 (CoA/Disconnect)         │
        └──────────────────────────┬───────────────────────────────────┘
                                   │ WireGuard :51820
                ┌──────────────────┴───────────────────────────────────┐
                │ droplet 10.10.10.1  FreeRADIUS 3.0 + RADIUSDesk     │
                │ RADIUS Client "Njeremoto Cafe Router" (Mikrotik)     │
                │ Profiles -> vouchers (user=pass) + permanent users   │
                └──────────────────────────────────────────────────────┘
```

## 2. Hardware & final state

| Item | Value |
|------|-------|
| Router | MikroTik hAP lite (RB941-2nD): 650 MHz MIPS, 32 MB RAM, **2.4 GHz only** (no 5 GHz radio) |
| RouterOS | 7.22.2 |
| Identity | `njeremoto-cafe-01` (drives RADIUSDesk "New Arrivals" onboarding via NAS-Identifier) |
| WAN uplink | `wlan1` in station mode → Cudy "Cudy-Outdoor" 2.4 GHz (ch 11) |
| LAN | bridge `192.168.88.1/24`, hotspot pool `192.168.88.2-254` |
| Tunnel | WireGuard `10.10.10.2/32` (router) ↔ `10.10.10.1` (droplet) |
| RADIUS | hotspot → `10.10.10.1` (site-wide secret), CoA on UDP 1700 |
| Fasttrack | **disabled** (required so per-user queues apply) |

## 3. Credentials & access (values redacted)

All passwords, PSKs, keys and the RADIUS site secret are `<redacted>`. Real
values live on the systems (see the list below).

| What | Value |
|------|-------|
| Cudy 2.4 GHz PSK (SSID "Cudy-Outdoor") | `<redacted>` |
| Cudy 5 GHz PSK (different SSID) | `<redacted>` |
| Router break-glass hotspot user | `admin` / `<redacted>` |
| RADIUSDesk UI login | `root` / `<redacted>` |
| RADIUSDesk site-wide RADIUS secret | `<redacted>` |
| RADIUSDesk MySQL | db `rd`, user `rd`, pass `<redacted>` |
| Owner permanent user | `owner@dev` / `<redacted>` |
| Droplet SSH | `root@165.232.33.196` (key `~/.ssh/<droplet-key>`) |
| Router SSH | `admin@192.168.88.1` (laptop key), `admin@10.10.10.2` (droplet key) |

Note: the router's web/WinBox admin password was **not set during this build** —
management is via SSH keys installed under `/user ssh-keys`.

### WireGuard keys

| Item | Value |
|------|-------|
| Router `wg1` public key | `<redacted>` (router: `/interface wireguard get wg1 public-key`) |
| Droplet `wg0` public key | `<redacted>` (droplet: `wg show wg0`) |
| Endpoint / port | `165.232.33.196:51820`, keepalive 25 s, mtu 1420 |
| Old (dead) router key | `<redacted>` (replaced after factory reset) |

### Where the real values live

- Router: `ssh admin@192.168.88.1` → `/export` (PSKs, break-glass, keys).
- Droplet: `/etc/wireguard/wg0.conf`, `wg show wg0`,
  `/etc/freeradius/3.0/sites-enabled/dynamic-clients` (site secret).
- RADIUSDesk GUI (admin credentials) and MySQL (`rd` database).

## 4. Profiles (RADIUSDesk → FreeRADIUS → RouterOS queues)

Both profiles share the rate `Mikrotik-Rate-Limit := 10M/5M 15M/8M 10M/5M 5/5`
(= sustained 10 Mbps down / 5 Mbps up, burst 15M/8M, threshold 10M/5M, burst 5 s).

| Profile | id | For | Time | Data | Devices |
|---------|----|-----|------|------|---------|
| `1 Hour Uncapped` | 49 | vouchers (user=pass) | 3600 s **hard** cap | none | `Simultaneous-Use := 1` |
| `Permanent` | 51 | permanent users | unlimited | none | `Simultaneous-Use := 1` |

radgroupcheck (SimpleAdd_49): `Rd-Reset-Type-Time := never`,
`Rd-Total-Time := 3600`, `Rd-Cap-Type-Time := hard`, `Simultaneous-Use := 1`.
radgroupcheck (SimpleAdd_51): `Simultaneous-Use := 1` only (no time/data).
radgroupreply (both): `Fall-Through := Yes`, `Mikrotik-Rate-Limit := <above>`.

## 5. Repository layout

```
README.md                         this file (complete reference)
SESSION-LOG.md                    full session dump for future agents to mine
mikrotik/
├── README.md                     router runbook: run order, verification, gotchas, failure modes
├── 01-network-wan.rsc            bridge->router, WAN/LAN split, NAT, DNS, identity (AS-BUILT)
├── 02-wireguard.rsc              tunnel to droplet
├── 03-hotspot-radius.rsc         hotspot + RADIUS client + CoA + conn-limit (AS-BUILT)
└── hotspot/                      custom login portal (uploads into the router's hotspot folder)
droplet/
├── README.md                     peer swap, firewall, RADIUSDesk onboarding, profiles/vouchers
└── update-wireguard-peer.sh      replaces the dead MikroTik peer key (live + wg0.conf)
```

## 6. Order of operations (reproduce from scratch)

1. `mikrotik/README.md` → run Phase 1–3 scripts on the router (one at a time).
2. `droplet/update-wireguard-peer.sh <new key>` on the droplet.
3. Reboot router → onboard in RADIUSDesk (**RADIUS Clients → New Arrivals**).
4. Create profiles → vouchers (user=pass) + permanent users → test.

Key design decisions:

- **RADIUS via the WireGuard tunnel** — the RADIUS client uses the tunnel IP, so
  Starlink's changing public IP never breaks authentication.
- **RADIUSDesk RADIUS Client (not NAS-style)** — identity-driven onboarding,
  type Mikrotik, auto-close stale sessions (3600 s), live accounting.
- **Local custom login page** — the Njeremoto-branded page with voucher and
  username/password tabs, served from the router (CHAP via md5.js).
- **Persistent keepalive 25 s** keeps the tunnel alive through Starlink NAT.

## 7. Router config (as-built, per script)

- **01**: identity, `wlan1` removed from bridge → WAN list, `mode=station`
  (station-pseudobridge flaps), explicit 2.4 GHz PSK, WAN DHCP client
  `cudy-starlink-wan`, DNS `94.140.14.14,94.140.15.15` (AdGuard), break-glass.
- **02**: `wg1` 10.10.10.2/32, listen 13231, peer → droplet, keepalive 25 s;
  **static route** `/ip route add dst-address=10.10.10.1/32 gateway=wg1`
  (RouterOS did NOT auto-create a route from the peer's allowed-address).
- **03**: `/radius` (hotspot, site secret, 5000 ms,
  `require-message-auth=yes-for-request-resp`), `/radius incoming accept=yes
  port=1700`, `wg1` into LAN list, hotspot DHCP pool, MAC-bypass the mgmt laptop
  **before** enabling hotspot, disable fasttrack, `hsprof1` (`use-radius`,
  `radius-accounting`, `radius-interim-update=00:10:00`, `login-by=http-chap,http-pap,cookie`,
  `html-directory=hotspot`), `hotspot1` on bridge (`idle-timeout=5m`), conn-limit
  firewall rule (see below).

### Robustness additions (live)

| Change | Where | Value |
|--------|-------|-------|
| Per-device connection cap | `/ip firewall filter` rule 23 | `chain=forward src-address=192.168.88.0/24 connection-state=new connection-limit=300,32 action=drop` |
| Ad-blocking DNS | `/ip dns` | `94.140.14.14,94.140.15.15` (AdGuard) — applies to all hotspot clients (they resolve via 192.168.88.1) |

## 8. Droplet config

- FreeRADIUS 3.0 + RADIUSDesk (CakePHP 4, `/var/www/rdcore/cake4/rd_cake`).
- Site-wide secret in `/etc/freeradius/3.0/sites-enabled/dynamic-clients`.
- UFW: `51820/udp`, `1812/udp` + `1813/udp` from `10.10.10.2`.
- **Time-cap bug fix** (see SESSION-LOG): `/etc/freeradius/3.0/policy.d/radiusdesk`
  `Rd-Used-Time` queries repointed to `SUM(acctsessiontime) FROM radacct ... AND
  acctstoptime IS NOT NULL`; same change in
  `src/Shell/Task/UsageTask.php` (`time_usage`, `time_usage_for_mac`,
  `find_no_reset_time_usage`); cron restored at `/etc/cron.d/radiusdesk` (6 jobs).
  Backups at `/root/freeradius-backups/`.

## 9. Gotchas (full list)

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| WiFi flaps `unicast key exchange timeout` | wrong PSK + `station-pseudobridge` flaps unbridged | correct PSK + `mode=station` |
| WG handshake OK, no data | no auto route on ROS 7.22.2 | static route `10.10.10.1/32 gateway=wg1` |
| Rate limits ignored | fasttrack bypasses queues | disable fasttrack |
| CoA NAK `Unsupported-Extension` | RouterOS matches sessions by host IP | include `Framed-IP-Address` in Disconnect-Request |
| SSH refused after hotspot on | hotspot firewall blocks non-bypassed hosts | MAC ip-binding bypass first |
| Mgmt IP changed (.254→.253) | DHCP swap re-leased the laptop | bypass by MAC, not IP |
| RADIUS timeouts after reboot | Accounting-On before tunnel handshake | self-heals via retries |
| Time cap never expires | `user_stats` triggers set created==timestamp → Rd-Used-Time=0, and cron missing | policy.d + UsageTask repoint + cron |
| A `.bak` in `policy.d/` overrode edits | `$INCLUDE policy.d/` loads every file | moved backups out of `policy.d/` |
| "Slow" internet on 1 device | 2M/1M profile cap (see §11) | raised to 10M/5M |

## 10. Verification (all live results)

| # | Check | Result |
|---|-------|--------|
| 1 | Tunnel | ✓ ~200 ms pings; keepalive keeps it alive |
| 2 | Captive portal | ✓ HTTP → redirect to `192.168.88.1/login` |
| 3 | Custom page | ✓ "Njeremoto Internet hotspot" + voucher tab |
| 4 | Voucher login | ✓ CHAP (user=pass) accepted |
| 5 | Time cap | ✓ `SESSION-TIME-LEFT` counts down from 1 h |
| 6 | Rate limit | ✓ dynamic queue `max-limit=10M/5M`, `burst-limit=15M/8M` |
| 7 | 1-device | ✓ 2nd login → `Access-Reject "Simultaneous connections limited to 1"` |
| 8 | Accounting | ✓ Start/Stop rows, byte counters both directions |
| 9 | Disconnect | ✓ CoA `Disconnect-ACK`, `acctterminatecause=Admin-Reset` |
| 10 | Reboot | ✓ unattended recovery; Accounting-On retried until tunnel up |
| 11 | Conn-limit | ✓ 350-conn flood → 299 through, 51 dropped at 300 cap |
| 12 | Ad-blocking | ✓ `doubleclick.net` → `0.0.0.0`, normal sites resolve |
| 13 | Permanent user | ✓ `owner@dev` no time cap, burst queue, 1-device limit |

## 11. The "internet is really slow" debugging saga (2026-09-11)

Timeline of the investigation (full narrative in SESSION-LOG.md):

1. User reported 1 device on the network was "really slow".
2. Client `shadowylaugh` was on the voucher profile → queue `max-limit=2M/1M`,
   and the queue showed **34,881 dropped download packets** (slammed into cap).
3. Router's own `wlan1` RX showed ~1.28 Mbps, and RouterOS `/tool fetch` gave
   ~0.6–0.85 Mbps → first hypothesis was "the 2.4 GHz WAN uplink is the bottleneck".
4. Cross-check: the mgmt laptop's WiFi (Cudy → Starlink) pulled **84 Mbps** to the
   same CDN → Starlink was fine.
5. User connected the laptop directly to the **same 2.4 GHz Cudy network** → **30 Mbps**.
   This proved the 2.4 GHz band/AP was fine.
6. **Root cause:** the earlier "~1 Mbps WAN" reading was an artifact of RouterOS's
   weak single-stream `fetch` client (small TCP window over the satellite RTT),
   NOT the real link. The real bottleneck was the **2 Mbps profile cap**.
7. **Fix:** raised both profiles to `10M/5M` (burst `15M/8M`). Confirmed fast.

Lesson: don't trust RouterOS `/tool fetch` for throughput — use a real client
(e.g. `curl` from a device behind the router, or the client's own speed test).

## 12. Operations cheatsheet

- **Reach the router** (mgmt): `ssh admin@192.168.88.1` (laptop) or hop the droplet
  `ssh root@165.232.33.196` → `ssh admin@10.10.10.2`.
- **RADIUSDesk API** (authenticate then act):
  `curl -sk -X POST https://radius.giftmugweni.com/cake4/rd_cake/dashboard/authenticate.json
  -d 'token=...&username=root&password=...'` → returns a token; pass `token=` in
  subsequent POST bodies. Base `/cake4/rd_cake/`.
- **Re-tier rate**: edit `radgroupreply.Mikrotik-Rate-Limit` for `SimpleAdd_49` /
  `SimpleAdd_51` (MySQL `rd`). New logins pick it up (existing sessions must re-login).
- **Kick a user**: CoA Disconnect from droplet
  `radclient -x 10.10.10.2:1700 disconnect "<site secret>"` with
  `Acct-Session-ID` + `Framed-IP-Address` (both required).

## 13. Full session dump

See `SESSION-LOG.md` for a complete chronological transcript of the entire
project (build phases, the time-cap bug, capacity analysis, robustness work, and
the slow-internet debugging) — intended for future agents to reconstruct full
context.
