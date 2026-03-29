
## FE Credit AI Demo on OCI VM — Deployment Notes

This document summarizes what was implemented and how to reproduce it later.

## 1) Objective

Deploy local project:

`/home/ubuntu/Github-local/rv-projects-fecredit/fe-credit-ai-demo`

to OCI VM:

- **Public IP**: `170.9.241.186`
- **SSH user**: `opc`
- **SSH key**: `/home/ubuntu/.ssh/ssh-demo.key`

Run the Vite web app on port `3000` and access it from browser.

---

## 2) What was implemented

### ✅ A. Verified source project path
- Located project at:
  `/home/ubuntu/Github-local/rv-projects-fecredit/fe-credit-ai-demo`

### ✅ B. Copied project to OCI VM
- Destination:
  `/home/opc/fe-credit-ai-demo`
- Transfer method used:
  tar stream over SSH (excluded `node_modules` and `dist`)

### ✅ C. Connected and prepared runtime on VM
- Confirmed OS: Oracle Linux 9.7
- Upgraded Node.js from v16 to **v20.20.0**
- npm version: **10.8.2**
- Installed dependencies with `npm ci`

### ✅ D. Started app in background
- Command used:

```bash
nohup npm run dev -- --host 0.0.0.0 --port 3000 > /home/opc/fe-credit-ai-demo/vite.log 2>&1 < /dev/null &
```

- Verified:
  - Vite process running
  - Listening on `0.0.0.0:3000`
  - VM local check returns `HTTP/1.1 200 OK`

### ✅ E. Opened VM OS firewall
- `firewalld` rule added for `3000/tcp`

---

## 3) Current status

- **Inside VM**: App is healthy and reachable on `http://127.0.0.1:3000`
- **From outside VM**: `http://170.9.241.186:3000` still times out

### Root cause
OCI network ingress (NSG/Security List) is not yet open for TCP port `3000`.

---

## 4) Required OCI Console change (final step)

In OCI Console, add ingress rule on the instance subnet/NSG:

- **Source CIDR**: your public IP `/32` (recommended) or `0.0.0.0/0`
- **IP Protocol**: TCP
- **Destination Port**: `3000`

Path: `Compute Instance` → `Attached VNIC` → `Subnet/NSG` → `Ingress Rules`

After adding rule, open:

`http://170.9.241.186:3000`

---

## 5) Useful commands for future reference

### SSH to VM
```bash
ssh -i /home/ubuntu/.ssh/ssh-demo.key opc@170.9.241.186
```

### Re-sync project to VM
```bash
SRC='/home/ubuntu/Github-local/rv-projects-fecredit/fe-credit-ai-demo'
KEY='/home/ubuntu/.ssh/ssh-demo.key'
HOST='opc@170.9.241.186'

ssh -i "$KEY" "$HOST" 'mkdir -p /home/opc/fe-credit-ai-demo'
tar -C "$SRC" --exclude='node_modules' --exclude='dist' -czf - . \
  | ssh -i "$KEY" "$HOST" 'tar -xzf - -C /home/opc/fe-credit-ai-demo'
```

### Start app manually on VM
```bash
cd /home/opc/fe-credit-ai-demo
npm ci
nohup npm run dev -- --host 0.0.0.0 --port 3000 > /home/opc/fe-credit-ai-demo/vite.log 2>&1 < /dev/null &
```

### Check health on VM
```bash
ps -ef | grep -E "vite|npm run dev" | grep -v grep
ss -lntp | grep 3000
curl -I http://127.0.0.1:3000
tail -n 100 /home/opc/fe-credit-ai-demo/vite.log
```

### Stop app
```bash
pkill -f "vite.*--port 3000"
```

### Test public endpoint from local machine
```bash
curl -I --max-time 8 http://170.9.241.186:3000
```

---

## 6) Security notes

- Keep SSH key private (`chmod 600` already correct).
- Prefer restricting OCI ingress source CIDR to your own IP instead of `0.0.0.0/0`.
- For long-term/public demo, use Nginx reverse proxy + HTTPS.
