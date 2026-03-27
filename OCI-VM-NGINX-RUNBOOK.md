# Simple Web App on OCI Compute (NGINX) — Runbook

## 1) Objective

Deploy a simple static web app to your OCI tenancy using:
- OCI Compute VM (Oracle Linux)
- NGINX web server
- Public subnet + NSG rules (22 restricted to your IP, 80 public)

This runbook uses the files in this folder:
- `index.html`
- `styles.css`
- `app.js`
- `cloud-init-nginx.sh`
- `deploy-to-oci-nginx.sh`

---

## 2) Assumptions / unknowns

You still need to provide these tenancy-specific values in `deploy-to-oci-nginx.sh`:
- `COMPARTMENT_OCID`
- `SUBNET_OCID` (public subnet)
- `AD_NAME`
- `IMAGE_OCID` (Oracle Linux image in your region)
- SSH key paths (default points to `/home/ubuntu/.ssh/id_rsa(.pub)`)
- `SSH_USER` (default is `opc` for Oracle Linux)

---

## 3) Recommended architecture

Client Browser
  -> Internet
  -> OCI VCN (public subnet)
  -> NSG (allow 80 from 0.0.0.0/0, allow 22 only from your public IP)
  -> OCI Compute (Oracle Linux)
  -> NGINX
  -> Static files under `/var/www/html`

---

## 4) Implementation plan

1. Configure OCI CLI locally
2. Prepare/confirm VCN + public subnet
3. Edit deployment script variables
4. Launch VM + bootstrap NGINX via cloud-init
5. Upload static app files
6. Validate HTTP and health endpoint

---

## 5) Artifacts (CLI / code)

## 5.1 Prerequisites

```bash
# OCI CLI should already be installed
oci --version

# Configure profile if not configured yet
oci setup config

# Check that your SSH key exists (or create one)
ls -l /home/ubuntu/.ssh/id_rsa /home/ubuntu/.ssh/id_rsa.pub
```

## 5.2 Get AD and Oracle Linux IMAGE OCID

```bash
# List availability domains
oci iam availability-domain list --compartment-id <TENANCY_OCID> \
  --query 'data[].name' --output table

# Find Oracle Linux image OCID in your region (example filter)
oci compute image list \
  --compartment-id <COMPARTMENT_OCID> \
  --operating-system "Oracle Linux" \
  --shape "VM.Standard.E2.1.Micro" \
  --query 'data[0].id' --raw-output
```

## 5.3 Edit deployment variables

Open and update:
- `deploy-to-oci-nginx.sh`

Required fields:
- `COMPARTMENT_OCID`
- `SUBNET_OCID`
- `AD_NAME`
- `IMAGE_OCID`

## 5.4 Deploy

```bash
cd /home/ubuntu/Github-local/web-app
chmod +x deploy-to-oci-nginx.sh cloud-init-nginx.sh
./deploy-to-oci-nginx.sh
```

Expected output includes:
- `Public URL: http://<PUBLIC_IP>`
- `Health check: http://<PUBLIC_IP>/healthz`

---

## 6) Validation checklist

- [ ] `http://<PUBLIC_IP>` loads the web page
- [ ] `http://<PUBLIC_IP>/healthz` returns `ok`
- [ ] SSH works only from your current IP
- [ ] Browser console has no major JS errors

Quick checks:

```bash
curl -i http://<PUBLIC_IP>/healthz
curl -I http://<PUBLIC_IP>/
```

---

## 7) Security checklist

- [ ] SSH (22) restricted to `/32` source IP only
- [ ] Port 80 allowed publicly only if needed
- [ ] No secrets stored in HTML/JS or committed scripts
- [ ] Use least-privilege IAM for OCI CLI/API keys
- [ ] Rotate API keys and restrict compartment scope

---

## 8) Cost & timeline (rough)

Cost drivers:
- Compute shape hours
- Boot volume size
- Public egress traffic

Typical timeline:
- 15–30 minutes for first deployment (including OCID lookup)
- 5–10 minutes for redeploy/update

---

## 9) Risks and mitigations

- Wrong AD/image/shape combination -> verify image and shape compatibility first
- Overly open network rules -> keep SSH source restricted to your IP
- Region/compartment mismatch -> confirm CLI profile region and OCIDs before deploy
- Demo downtime during changes -> upload changes first, then restart NGINX once

---

## Optional cleanup (avoid unnecessary cost)

After demo, terminate the VM and remove NSG from OCI Console, or via CLI:

```bash
oci compute instance terminate --instance-id <INSTANCE_OCID> --force
oci network nsg delete --nsg-id <NSG_OCID> --force
```
