#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# Simple Web App deployment to OCI Compute VM (Oracle Linux + NGINX)
# -------------------------------------------------------------------
# Prereqs:
# 1) OCI CLI configured: `oci setup config`
# 2) Existing VCN + Public Subnet
# 3) SSH keypair available locally
#
# Usage:
#   chmod +x deploy-to-oci-nginx.sh
#   ./deploy-to-oci-nginx.sh
# -------------------------------------------------------------------

# ===== Required values (edit before run) =====
COMPARTMENT_OCID="ocid1.compartment.oc1..replace_me"
SUBNET_OCID="ocid1.subnet.oc1..replace_me"
AD_NAME="gYVL:AP-SINGAPORE-1-AD-1"  # e.g. from: oci iam availability-domain list
IMAGE_OCID="ocid1.image.oc1.ap-singapore-1.replace_me" # Oracle Linux image OCID
SSH_PUBLIC_KEY_PATH="/home/ubuntu/.ssh/id_rsa.pub"
SSH_PRIVATE_KEY_PATH="/home/ubuntu/.ssh/id_rsa"

# ===== Optional values =====
REGION="ap-singapore-1"
INSTANCE_SHAPE="VM.Standard.E2.1.Micro"
INSTANCE_DISPLAY_NAME="simple-web-nginx"
NSG_DISPLAY_NAME="nsg-simple-web-nginx"
SSH_USER="opc"

echo "[1/7] Checking dependencies"
command -v oci >/dev/null
command -v curl >/dev/null
command -v scp >/dev/null
command -v ssh >/dev/null
test -f "$SSH_PUBLIC_KEY_PATH"
test -f "$SSH_PRIVATE_KEY_PATH"

echo "[2/7] Creating NSG"
NSG_ID=$(oci network nsg create \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$(oci network subnet get --subnet-id "$SUBNET_OCID" --query 'data."vcn-id"' --raw-output)" \
  --display-name "$NSG_DISPLAY_NAME" \
  --query 'data.id' --raw-output)

MY_IP_CIDR="$(curl -s ifconfig.me)/32"

echo "[3/7] Adding NSG ingress rules (22 from my IP, 80 public)"
oci network nsg rules add \
  --nsg-id "$NSG_ID" \
  --security-rules "[
    {\"direction\":\"INGRESS\",\"protocol\":\"6\",\"source\":\"${MY_IP_CIDR}\",\"sourceType\":\"CIDR_BLOCK\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}}},
    {\"direction\":\"INGRESS\",\"protocol\":\"6\",\"source\":\"0.0.0.0/0\",\"sourceType\":\"CIDR_BLOCK\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":80,\"max\":80}}}
  ]" >/dev/null

echo "[4/7] Launching compute instance"
USER_DATA_B64=$(base64 -w 0 cloud-init-nginx.sh)

INSTANCE_ID=$(oci compute instance launch \
  --compartment-id "$COMPARTMENT_OCID" \
  --availability-domain "$AD_NAME" \
  --shape "$INSTANCE_SHAPE" \
  --display-name "$INSTANCE_DISPLAY_NAME" \
  --image-id "$IMAGE_OCID" \
  --subnet-id "$SUBNET_OCID" \
  --assign-public-ip true \
  --nsg-ids "[\"$NSG_ID\"]" \
  --metadata "{\"ssh_authorized_keys\":\"$(cat "$SSH_PUBLIC_KEY_PATH")\",\"user_data\":\"$USER_DATA_B64\"}" \
  --query 'data.id' --raw-output)

echo "[5/7] Waiting until instance is RUNNING"
oci compute instance get --instance-id "$INSTANCE_ID" --wait-for-state RUNNING >/dev/null

VNIC_ID=$(oci compute instance list-vnics \
  --instance-id "$INSTANCE_ID" \
  --query 'data[0].id' --raw-output)

PUBLIC_IP=$(oci network vnic get \
  --vnic-id "$VNIC_ID" \
  --query 'data."public-ip"' --raw-output)

echo "[6/7] Uploading web files"
scp -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
  index.html styles.css app.js "$SSH_USER"@"$PUBLIC_IP":/tmp/

echo "[7/7] Publishing files to NGINX web root"
ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER"@"$PUBLIC_IP" \
  "sudo cp /tmp/index.html /tmp/styles.css /tmp/app.js /var/www/html/ && sudo systemctl restart nginx"

echo ""
echo "Deployment complete"
echo "Instance OCID: $INSTANCE_ID"
echo "Public URL:    http://$PUBLIC_IP"
echo "Health check:  http://$PUBLIC_IP/healthz"
