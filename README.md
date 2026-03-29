# ==== OCI VM info ====

- **Public IP**: `170.9.241.186`
- **SSH user**: `opc`
- **SSH key**: `/home/ubuntu/.ssh/ssh-demo.key`

## There are 2 folders in OCI VM:
- fe-credit-ai-demo
- simple-web-app

I’ve already configured NGINX so you can open each app separately by URL path on the same VM/IP.

Use these URLs:

- __simple-web-app__: `http://170.9.241.186/simple-web-app/`
- __fe-credit-ai-demo__: `http://170.9.241.186/fe-credit/`

I validated both endpoints from outside the VM and both return __HTTP 200 OK__.


## Explaination:  how to set it up so both apps open separately on the **same VM/IP**.

### 1) Used **path-based routing** in one NGINX server block
Instead of different ports or domains, I mapped URL paths:
- `/simple-web-app/` → simple static app
- `/fe-credit/` → FE Credit app

So users access:
- `http://170.9.241.186/simple-web-app/`
- `http://170.9.241.186/fe-credit/`

---

### 2) Pointed each path to a different folder with `alias`
I created NGINX locations in `/etc/nginx/default.d/multi-app.conf`:

```nginx
location = /simple-web-app { return 301 /simple-web-app/; }
location /simple-web-app/ {
    alias /usr/share/nginx/html/simple-web-app/;
    index index.html;
}

location = /fe-credit { return 301 /fe-credit/; }
location /fe-credit/ {
    alias /home/opc/fe-credit-ai-demo/;
    index index.html;
}
```

This is the key to serving multiple apps from one public IP: each URL prefix maps to its own directory.

---

### 3) Fixed FE Credit blank page issue (important)
The FE app’s original `index.html` referenced dev files (`/src/main.tsx`), which do not render in plain NGINX static mode. That caused the “blank page” behavior.

So I:
1. Built FE app for production with path prefix:
   - `npm run build -- --base=/fe-credit/`
2. Replaced `/home/opc/fe-credit-ai-demo/index.html` with built `dist/index.html`
3. Copied built assets from `dist/assets/` to `/home/opc/fe-credit-ai-demo/assets/`

Now FE HTML points to `/fe-credit/assets/...` and loads correctly.

---

### 4) Allowed NGINX to read files under `/home/opc`
Because FE app is served from `/home/opc/fe-credit-ai-demo`, I ensured access with SELinux + home-dir policy:
- Enabled `httpd_enable_homedirs`
- Applied `httpd_sys_content_t` context on FE folder

This removed permission-denied behavior when serving from home directories.

---

### 5) Reloaded and validated
After `nginx -t` + reload, I verified:
- `/fe-credit/` → HTTP 200
- FE JS asset under `/fe-credit/assets/...` → HTTP 200
- `/simple-web-app/` → HTTP 200

That confirms both apps are independently reachable via path routing on the same VM/IP.