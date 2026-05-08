---
description: Deploy the latest Galyarder Route code to BOTH the Akamai VPS and the Local VPS
---

# Deploy to VPS (Both) Workflow

Deploy Galyarder Route to the production VPSs using `npm pack + scp` + PM2.

**Akamai VPS:** `69.164.221.35`
**Local VPS:** `192.168.0.15`
**Process manager:** PM2 (`galyarder-route`)
**Port:** `20128`
**PM2 entry:** `/usr/lib/node_modules/galyarder-route/app/server.js`

> [!IMPORTANT]
> The npm registry rejects packages > 100MB, so deployment uses **npm pack + scp**.

## Steps

### 1. Build + pack locally

// turbo

```bash
cd /home/galyarderlabs/dev/proxys/Galyarder Route && rm -f galyarder-route-*.tgz && rm -rf .next/cache app/.next/cache && npm run build:cli && rm -rf app/logs app/coverage app/.git app/.app-build-backup* && npm pack --ignore-scripts
```

### 2. Copy to both VPS and install

// turbo-all

```bash
scp galyarder-route-*.tgz root@69.164.221.35:/tmp/ && scp galyarder-route-*.tgz root@192.168.0.15:/tmp/
```

```bash
ssh root@69.164.221.35 "npm install -g /tmp/galyarder-route-*.tgz --ignore-scripts && cd /usr/lib/node_modules/galyarder-route/app && npm rebuild better-sqlite3 && pm2 delete galyarder-route 2>/dev/null; pm2 start /root/.galyarder-route/ecosystem.config.cjs --update-env && pm2 save && echo '✅ Akamai done'"
```

```bash
ssh root@192.168.0.15 "npm install -g /tmp/galyarder-route-*.tgz --ignore-scripts && cd /usr/lib/node_modules/galyarder-route/app && npm rebuild better-sqlite3 && pm2 delete galyarder-route 2>/dev/null; pm2 start /root/.galyarder-route/ecosystem.config.cjs --update-env && pm2 save && echo '✅ Local done'"
```

### 3. Verify the deployment

```bash
curl -s -o /dev/null -w 'AKAMAI HTTP %{http_code}\n' http://69.164.221.35:20128/
curl -s -o /dev/null -w 'LOCAL HTTP %{http_code}\n' http://192.168.0.15:20128/
```
