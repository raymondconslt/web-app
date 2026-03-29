#!/bin/bash
set -euxo pipefail

dnf -y install nginx
systemctl enable nginx
systemctl start nginx

# If firewalld is enabled, allow HTTP
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http || true
  firewall-cmd --reload || true
fi

# Keep a simple health endpoint for quick checks
mkdir -p /usr/share/nginx/html
cat >/usr/share/nginx/html/healthz <<'HEALTH'
ok
HEALTH
