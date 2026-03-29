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
COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaa73hvct2toool4woa4dtwdh37frkfoijuzod5giqtjhwurt76f5mq"
SUBNET_OCID="ocid1.subnet.oc1.us-chicago-1.aaaaaaaaifltgunbye5fkp4ejjdjwgs4scedqdkq732em45np22vcjofgtmq"
AD_NAME="Zjxq:US-CHICAGO-1-AD-1"  # e.g. from: oci iam availability-domain list
IMAGE_OCID="ocid1.image.oc1.us-chicago-1.aaaaaaaalcrodfcn4buostm2lrtsckahbbjyjjct7anhbaeeqqkux7ht3nhq" # Oracle Linux image OCID
SSH_PUBLIC_KEY_PATH="/home/ubuntu/.ssh/ssh-demo.pub"
SSH_PRIVATE_KEY_PATH="/home/ubuntu/.ssh/ssh-demo.key"

# ===== Optional values =====
REGION="us-chicago-1"
INSTANCE_SHAPE="VM.Standard.E5.Flex"
INSTANCE_OCPUS="1"
INSTANCE_MEMORY_GBS="8"
INSTANCE_DISPLAY_NAME="simple-web-nginx"
NSG_DISPLAY_NAME="nsg-simple-web-nginx"
SSH_USER="opc"
WEB_ROOT="/usr/share/nginx/html"

echo "[1/7] Checking dependencies"
command -v oci >/dev/null
command -v curl >/dev/null
command -v scp >/dev/null
command -v ssh >/dev/null
test -f "$SSH_PUBLIC_KEY_PATH"
test -f "$SSH_PRIVATE_KEY_PATH"

echo "[2/7] Creating NSG"
NSG_ID=$(oci network nsg create \
  --region "$REGION" \
  --compartment-id "$COMPARTMENT_OCID" \
  --vcn-id "$(oci network subnet get --region "$REGION" --subnet-id "$SUBNET_OCID" --query 'data."vcn-id"' --raw-output)" \
  --display-name "$NSG_DISPLAY_NAME" \
  --query 'data.id' --raw-output)

MY_IP_CIDR="$(curl -s ifconfig.me)/32"

echo "[3/7] Adding NSG ingress rules (22 from my IP, 80 public)"
oci network nsg rules add \
  --region "$REGION" \
  --nsg-id "$NSG_ID" \
  --security-rules "[
    {\"direction\":\"INGRESS\",\"protocol\":\"6\",\"source\":\"${MY_IP_CIDR}\",\"sourceType\":\"CIDR_BLOCK\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}}},
    {\"direction\":\"INGRESS\",\"protocol\":\"6\",\"source\":\"0.0.0.0/0\",\"sourceType\":\"CIDR_BLOCK\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":80,\"max\":80}}}
  ]" >/dev/null

echo "[4/7] Launching compute instance"
USER_DATA_B64=$(base64 -w 0 cloud-init-nginx.sh)
SHAPE_CONFIG_JSON=$(printf '{"ocpus": %s, "memoryInGBs": %s}' "$INSTANCE_OCPUS" "$INSTANCE_MEMORY_GBS")

INSTANCE_ID=$(oci compute instance launch \
  --region "$REGION" \
  --compartment-id "$COMPARTMENT_OCID" \
  --availability-domain "$AD_NAME" \
  --shape "$INSTANCE_SHAPE" \
  --shape-config "$SHAPE_CONFIG_JSON" \
  --display-name "$INSTANCE_DISPLAY_NAME" \
  --image-id "$IMAGE_OCID" \
  --subnet-id "$SUBNET_OCID" \
  --assign-public-ip true \
  --nsg-ids "[\"$NSG_ID\"]" \
  --metadata "{\"ssh_authorized_keys\":\"$(cat "$SSH_PUBLIC_KEY_PATH")\",\"user_data\":\"$USER_DATA_B64\"}" \
  --query 'data.id' --raw-output)

echo "[5/7] Waiting until instance is RUNNING"
oci compute instance get --region "$REGION" --instance-id "$INSTANCE_ID" --wait-for-state RUNNING >/dev/null

VNIC_ID=$(oci compute instance list-vnics \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --query 'data[0].id' --raw-output)

PUBLIC_IP=$(oci network vnic get \
  --region "$REGION" \
  --vnic-id "$VNIC_ID" \
  --query 'data."public-ip"' --raw-output)

echo "Waiting for SSH on $PUBLIC_IP"
for i in {1..30}; do
  if ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER"@"$PUBLIC_IP" 'echo ssh-ready' >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: SSH did not become ready in time"
    exit 1
  fi
  sleep 10
done

echo "Waiting for NGINX to be active"
for i in {1..30}; do
  if ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER"@"$PUBLIC_IP" 'sudo systemctl is-active nginx' >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: NGINX did not become active in time"
    ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER"@"$PUBLIC_IP" 'sudo cloud-init status || true; sudo tail -n 80 /var/log/cloud-init-output.log || true'
    exit 1
  fi
  sleep 10
done

echo "[6/7] Uploading web files"
scp -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no \
  index.html styles.css app.js "$SSH_USER"@"$PUBLIC_IP":/tmp/

echo "[7/7] Publishing files to NGINX web root"
ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER"@"$PUBLIC_IP" \
  "sudo mkdir -p '$WEB_ROOT' && sudo cp /tmp/index.html /tmp/styles.css /tmp/app.js '$WEB_ROOT/' && sudo systemctl restart nginx"

echo ""
echo "Deployment complete"
echo "Instance OCID: $INSTANCE_ID"
echo "Public URL:    http://$PUBLIC_IP"
echo "Health check:  http://$PUBLIC_IP/healthz"
