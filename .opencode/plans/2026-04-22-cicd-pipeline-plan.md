# CI/CD Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a multi-job GitHub Actions workflow that deploys a RADIUS + WireGuard stack to a DigitalOcean droplet on push to main, with validation, secret rendering, smoke testing, and automatic rollback.

**Architecture:** Six sequential jobs (validate → render → deploy → smoke-test → rollback → notify) using artifacts to pass the rendered compose file between stages. Secrets stored in GitHub, substituted via Python to avoid sed escaping issues.

**Tech Stack:** GitHub Actions, Docker Compose, Python, Gitleaks, SSH/SCP

---

### File Structure

| File | Purpose |
|------|---------|
| `.github/workflows/deploy.yml` | Main CI/CD pipeline workflow |
| `.gitleaks.toml` | Gitleaks config to allowlist `{{PLACEHOLDER}}` template patterns |
| `docker-compose.yml` | Modify web ports to bind to `127.0.0.1` only |
| `.gitignore` | Add `.bak` files and rendered compose files |

---

### Task 1: Add Gitleaks Configuration

**Files:**
- Create: `.gitleaks.toml`

- [ ] **Step 1: Create `.gitleaks.toml`**

```toml
title = "gitleaks config"

[allowlist]
description = "Allowlist template placeholders in docker-compose.yml"
paths = [
    '''docker-compose\.yml''',
]
regexes = [
    '''\{\{[A-Z_]+\}\}''',
]
```

This prevents gitleaks from flagging `{{RADIUS_DB_ROOT_PASSWORD}}` etc. as actual secrets.

- [ ] **Step 2: Commit**

```bash
git add .gitleaks.toml
git commit -m "chore: add gitleaks config to allowlist template patterns"
```

---

### Task 2: Update docker-compose.yml for Localhost Binding

**Files:**
- Modify: `docker-compose.yml`

- [ ] **Step 1: Update port bindings**

Change web service ports to bind to `127.0.0.1` only, since host-level nginx will reverse proxy. RADIUS and WireGuard ports remain public.

```yaml
version: '3.8'

services:
  radius-db:
    image: mariadb:10.5
    container_name: radius-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD={{RADIUS_DB_ROOT_PASSWORD}}
      - MYSQL_DATABASE=radius
      - MYSQL_USER=radius
      - MYSQL_PASSWORD={{RADIUS_DB_PASSWORD}}
    volumes:
      - radius-db-data:/var/lib/mysql

  daloradius:
    image: lirantal/daloradius:latest
    container_name: daloradius
    restart: unless-stopped
    depends_on:
      - radius-db
    ports:
      - "127.0.0.1:80:80"
      - "1812:1812/udp"
      - "1813:1813/udp"
    environment:
      - MYSQL_HOST=radius-db
      - MYSQL_PORT=3306
      - MYSQL_DATABASE=radius
      - MYSQL_USER=radius
      - MYSQL_PASSWORD={{RADIUS_DB_PASSWORD}}
      - TZ=Africa/Harare
    volumes:
      - daloradius-logs:/var/log/freeradius

  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    environment:
      - WG_HOST={{DROPLET_IP}}
      - PASSWORD_HASH={{WG_EASY_PASSWORD_HASH}}
      - WG_PORT=51820
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=1.1.1.1
    volumes:
      - wg-easy-data:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "127.0.0.1:51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1

volumes:
  radius-db-data:
  daloradius-logs:
  wg-easy-data:
```

Changes:
- `"80:80"` → `"127.0.0.1:80:80"` (daloRADIUS)
- `"51821:51821/tcp"` → `"127.0.0.1:51821:51821/tcp"` (wg-easy GUI)

- [ ] **Step 2: Validate locally**

```bash
docker compose config
```

Expected: No errors, YAML parses correctly.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "chore: bind web service ports to localhost for nginx reverse proxy"
```

---

### Task 3: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add ignore patterns**

```
*.bak
docker-compose.rendered.yml
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add backup and rendered compose files to gitignore"
```

---

### Task 4: Create the GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: Deploy to DigitalOcean

on:
  push:
    branches: [main]

jobs:
  validate:
    name: Validate
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Validate docker-compose syntax
        run: docker compose config

      - name: Scan for secrets
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  render:
    name: Render Compose File
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Render docker-compose.yml
        run: |
          python3 -c "
          import re, os
          with open('docker-compose.yml', 'r') as f:
              content = f.read()
          replacements = {
              '{{RADIUS_DB_ROOT_PASSWORD}}': os.environ['RADIUS_DB_ROOT_PASSWORD'],
              '{{RADIUS_DB_PASSWORD}}': os.environ['RADIUS_DB_PASSWORD'],
              '{{DROPLET_IP}}': os.environ['DROPLET_IP'],
              '{{WG_EASY_PASSWORD_HASH}}': os.environ['WG_EASY_PASSWORD_HASH'],
          }
          for placeholder, value in replacements.items():
              content = content.replace(placeholder, value)
          with open('docker-compose.rendered.yml', 'w') as f:
              f.write(content)
          "
        env:
          RADIUS_DB_ROOT_PASSWORD: ${{ secrets.RADIUS_DB_ROOT_PASSWORD }}
          RADIUS_DB_PASSWORD: ${{ secrets.RADIUS_DB_PASSWORD }}
          DROPLET_IP: ${{ secrets.DROPLET_IP }}
          WG_EASY_PASSWORD_HASH: ${{ secrets.WG_EASY_PASSWORD_HASH }}

      - name: Upload rendered compose file
        uses: actions/upload-artifact@v4
        with:
          name: deploy-artifact
          path: docker-compose.rendered.yml
          retention-days: 1

  deploy:
    name: Deploy to Droplet
    runs-on: ubuntu-latest
    needs: render
    steps:
      - name: Download rendered compose file
        uses: actions/download-artifact@v4
        with:
          name: deploy-artifact

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DO_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H ${{ secrets.DO_HOST }} >> ~/.ssh/known_hosts

      - name: Backup current compose on droplet
        run: |
          ssh ${{ secrets.DO_USER }}@${{ secrets.DO_HOST }} \
            "cd ~/cafe-radius && cp docker-compose.yml docker-compose.yml.bak 2>/dev/null || true"

      - name: SCP rendered compose to droplet
        run: |
          scp docker-compose.rendered.yml \
            ${{ secrets.DO_USER }}@${{ secrets.DO_HOST }}:~/cafe-radius/docker-compose.yml

      - name: Restart containers
        run: |
          ssh ${{ secrets.DO_USER }}@${{ secrets.DO_HOST }} \
            "cd ~/cafe-radius && docker compose down && docker compose up -d"

  smoke-test:
    name: Smoke Test
    runs-on: ubuntu-latest
    needs: deploy
    steps:
      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DO_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H ${{ secrets.DO_HOST }} >> ~/.ssh/known_hosts

      - name: Wait for services to start
        run: sleep 15

      - name: Run smoke tests
        run: |
          ssh ${{ secrets.DO_USER }}@${{ secrets.DO_HOST }} bash -s << 'EOF'
            set -e

            echo "Checking container health..."
            cd ~/cafe-radius
            docker compose ps --format json | python3 -c "
            import sys, json
            containers = []
            for line in sys.stdin:
                if line.strip():
                    containers.append(json.loads(line))
            for c in containers:
                if 'running' not in c.get('State', '').lower():
                    print(f'  FAIL: {c[\"Name\"]} is {c[\"State\"]}')
                    sys.exit(1)
                print(f'  OK: {c[\"Name\"]} is running')
            "

            echo "Testing daloRADIUS HTTP (port 80)..."
            curl -sf http://127.0.0.1:80 > /dev/null && echo "  OK" || { echo "  FAIL"; exit 1; }

            echo "Testing wg-easy GUI HTTP (port 51821)..."
            curl -sf http://127.0.0.1:51821 > /dev/null && echo "  OK" || { echo "  FAIL"; exit 1; }

            echo "All smoke tests passed!"
          EOF

  rollback:
    name: Rollback
    runs-on: ubuntu-latest
    needs: smoke-test
    if: failure()
    steps:
      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DO_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H ${{ secrets.DO_HOST }} >> ~/.ssh/known_hosts

      - name: Restore previous compose and restart
        run: |
          ssh ${{ secrets.DO_USER }}@${{ secrets.DO_HOST }} bash -s << 'EOF'
            cd ~/cafe-radius
            if [ -f docker-compose.yml.bak ]; then
              cp docker-compose.yml.bak docker-compose.yml
              docker compose down
              docker compose up -d
              echo "Rollback completed successfully."
            else
              echo "No backup found, skipping rollback."
              exit 1
            fi
          EOF

  notify:
    name: Notify
    runs-on: ubuntu-latest
    needs: [deploy, smoke-test, rollback]
    if: always()
    steps:
      - name: Report workflow status
        run: |
          DEPLOY_STATUS="${{ needs.deploy.result }}"
          SMOKE_STATUS="${{ needs.smoke-test.result }}"
          ROLLBACK_STATUS="${{ needs.rollback.result }}"

          if [ "$SMOKE_STATUS" = "success" ]; then
            echo "::notice::Deployment succeeded. All services are running."
          elif [ "$ROLLBACK_STATUS" = "success" ]; then
            echo "::error::Deployment failed. Smoke tests failed. Rollback completed."
          else
            echo "::error::Deployment failed. Smoke tests failed. Rollback also failed."
          fi
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "feat: add CI/CD pipeline with validate, render, deploy, smoke-test, and rollback"
```

---

### Task 5: Verify Workflow Structure

- [ ] **Step 1: Validate workflow YAML syntax**

```bash
python3 -c "
import yaml
with open('.github/workflows/deploy.yml') as f:
    data = yaml.safe_load(f)
print('Jobs:', list(data['jobs'].keys()))
print('Workflow is valid YAML')
"
```

Expected output:
```
Jobs: ['validate', 'render', 'deploy', 'smoke-test', 'rollback', 'notify']
Workflow is valid YAML
```

- [ ] **Step 2: Verify all required secrets are referenced**

```bash
grep -o 'secrets\.[A-Z_]*' .github/workflows/deploy.yml | sort -u
```

Expected to include: `DO_HOST`, `DO_SSH_KEY`, `DO_USER`, `DROPLET_IP`, `RADIUS_DB_PASSWORD`, `RADIUS_DB_ROOT_PASSWORD`, `WG_EASY_PASSWORD_HASH`

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add .github/workflows/deploy.yml
git commit -m "fix: verify workflow structure and secret references"
```
