# CI/CD Pipeline Design — Hotspot Cafe Config

**Date:** 2026-04-22  
**Status:** Draft — awaiting user review

## Overview

Multi-job GitHub Actions workflow that deploys a RADIUS + WireGuard stack to a DigitalOcean droplet on every push to `main`. Includes validation, secret rendering, deployment, smoke testing, and automatic rollback on failure.

## Workflow Structure

```
validate → render → deploy → smoke-test
                                    ↓ (on failure)
                                 rollback → notify
```

### Jobs

| Job | Runs On | Purpose | Trigger |
|-----|---------|---------|---------|
| `validate` | ubuntu-latest | Compose syntax check + secret scanning | push to main |
| `render` | ubuntu-latest | Substitute secrets into compose file, upload artifact | validate succeeds |
| `deploy` | ubuntu-latest | SCP rendered compose, restart containers | render succeeds |
| `smoke-test` | ubuntu-latest | Verify all 5 services are responding | deploy succeeds |
| `rollback` | ubuntu-latest | Restore previous compose on failure | smoke-test fails |
| `notify` | ubuntu-latest | Report final workflow status | always |

## Required GitHub Secrets

| Secret | Purpose | Example |
|--------|---------|---------|
| `DO_HOST` | Droplet public IP | `159.89.100.1` |
| `DO_USER` | SSH user | `root` |
| `DO_SSH_KEY` | SSH private key for deployment | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `RADIUS_DB_ROOT_PASSWORD` | MariaDB root password | `radiusrootpass` |
| `RADIUS_DB_PASSWORD` | MariaDB radius user password | `radiusdbpass` |
| `WG_EASY_PASSWORD_HASH` | wg-easy web GUI password hash | `$2a$12$...` |
| `DROPLET_IP` | Droplet IP (used in WG_HOST) | `159.89.100.1` |

## Job Details

### 1. validate

- Run `docker compose config` to verify YAML syntax and structure
- Run `gitleaks` (via `gitleaks/gitleaks-action`) to scan for hardcoded secrets in the repo
- A `.gitleaks.toml` config file is added to the repo to allowlist the `{{PLACEHOLDER}}` template patterns and prevent false positives
- Fails fast if either check fails

### 2. render

- Read `docker-compose.yml` from repo
- Use Python (available on ubuntu-latest) to replace all `{{PLACEHOLDER}}` values with corresponding GitHub Secrets. Python avoids `sed` issues with special characters like `$`, `&`, `\` in password hashes:
  - `{{RADIUS_DB_ROOT_PASSWORD}}` → `secrets.RADIUS_DB_ROOT_PASSWORD`
  - `{{RADIUS_DB_PASSWORD}}` → `secrets.RADIUS_DB_PASSWORD`
  - `{{DROPLET_IP}}` → `secrets.DROPLET_IP`
  - `{{WG_EASY_PASSWORD_HASH}}` → `secrets.WG_EASY_PASSWORD_HASH`
- Write rendered file to temp directory
- Upload as GitHub Actions artifact named `deploy-artifact`

### 3. deploy

- Download `deploy-artifact`
- SSH to droplet and backup current compose file:
  ```bash
  cp ~/cafe-radius/docker-compose.yml ~/cafe-radius/docker-compose.yml.bak
  ```
- SCP rendered `docker-compose.yml` to `~/cafe-radius/docker-compose.yml`
- SSH to droplet and restart:
  ```bash
  cd ~/cafe-radius && docker compose down && docker compose up -d
  ```

### 4. smoke-test

- SSH to droplet and verify all services:
  ```bash
  curl -sf http://127.0.0.1:80        # daloRADIUS web
  curl -sf http://127.0.0.1:51821     # wg-easy web GUI
  nc -z -w5 127.0.0.1 1812            # RADIUS auth (UDP)
  nc -z -w5 127.0.0.1 1813            # RADIUS acct (UDP)
  nc -z -w5 -u 127.0.0.1 51820        # WireGuard (UDP)
  ```
- All 5 checks must pass. Any failure marks job as failed.

### 5. rollback

- Condition: `if: failure()` (only runs if smoke-test fails)
- SSH to droplet and restore:
  ```bash
  cd ~/cafe-radius && cp docker-compose.yml.bak docker-compose.yml && docker compose down && docker compose up -d
  ```

### 6. notify

- Condition: `if: always()`
- Reports final workflow status using GitHub's built-in notifications
- Uses `slackapi/slack-github-action` if `SLACK_WEBHOOK_URL` secret is configured (optional)

## Infrastructure Notes

- Web services (daloRADIUS on port 80, wg-easy on 51821) bind to `127.0.0.1` only — not publicly exposed
- Host-level nginx handles reverse proxy and SSL via certbot (managed manually)
- RADIUS ports (1812/1813 UDP) and WireGuard (51820 UDP) remain publicly accessible — these are not proxied by nginx
- Subdomains: `radius.giftmugweni.com` → daloRADIUS, `vpn.giftmugweni.com` → wg-easy

## docker-compose.yml Changes Required

Current compose file binds ports to all interfaces. The deployed version should bind web ports to localhost only:
- `"80:80"` → `"127.0.0.1:80:80"`
- `"51821:51821/tcp"` → `"127.0.0.1:51821:51821/tcp"`

RADIUS and WireGuard ports remain unchanged (public).

## Files to Create

```
.github/
  workflows/
    deploy.yml          # Main CI/CD pipeline
.gitleaks.toml          # Gitleaks config to allowlist template patterns
```
