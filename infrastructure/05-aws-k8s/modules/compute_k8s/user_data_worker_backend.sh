#!/bin/bash
set -e

# 1. System Updates & Prerequisites
dnf update -y
dnf install -y jq tar

# Terraform strictly injects these values here
REGION="${aws_region}"
ENVIRONMENT="${environment}"
NLB_DNS="${control_plane_endpoint}"
NODE_ROLE="backend"

# 2. Fetch the K3s Cluster Join Token from Secrets Manager
# (Curly braces removed)
TOKEN_SECRET_ID="rr-$ENVIRONMENT-k3s-join-token"

echo "Waiting for Control Plane to publish K3s join token..."
CLUSTER_TOKEN=""
while [ -z "$CLUSTER_TOKEN" ] || [ "$CLUSTER_TOKEN" == "None" ]; do
  CLUSTER_TOKEN=$(aws secretsmanager get-secret-value --region $REGION --secret-id $TOKEN_SECRET_ID --query SecretString --output text 2>/dev/null || echo "")
  if [ -z "$CLUSTER_TOKEN" ]; then
    echo "Token not ready. Retrying in 10 seconds..."
    sleep 10
  fi
done

# 3. Join the HA K3s Cluster with Backend Taints
# (Curly braces removed from NLB_DNS, CLUSTER_TOKEN, and NODE_ROLE)
echo "Joining K3s cluster via NLB: $NLB_DNS"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.15+k3s1" K3S_URL=https://$NLB_DNS:6443 K3S_TOKEN=$CLUSTER_TOKEN sh -s - agent \
  --node-taint dedicated=$NODE_ROLE:NoSchedule \
  --node-label tier=$NODE_ROLE