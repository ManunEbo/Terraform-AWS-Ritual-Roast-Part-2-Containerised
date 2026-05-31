#!/bin/bash
set -e

# 1. System Updates & Prerequisites
dnf update -y
dnf install -y jq tar openssl

REGION="${aws_region}"
ENVIRONMENT="${environment}"
NLB_DNS="${nlb_dns_name}"

# 2. Manage the K3s Cluster Join Token (Secrets Manager)
TOKEN_SECRET_ID="rr-${ENVIRONMENT}-k3s-join-token"

# If the secret doesn't exist, the first node to boot will create it
if ! aws secretsmanager describe-secret --region $REGION --secret-id $TOKEN_SECRET_ID > /dev/null 2>&1; then
  echo "Creating new K3s join token..."
  NEW_TOKEN=$(openssl rand -hex 16)
  aws secretsmanager create-secret --region $REGION --name $TOKEN_SECRET_ID --secret-string "$NEW_TOKEN" || true
fi

# Fetch the established token
K3S_TOKEN=$(aws secretsmanager get-secret-value --region $REGION --secret-id $TOKEN_SECRET_ID --query SecretString --output text)

# 3. HA Leader Election (Embedded etcd)
# Find all running CP nodes and sort by IP to deterministically pick the "Leader"
EXISTING_CP=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:Name,Values=rr-${ENVIRONMENT}-k3s-control-plane" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PrivateIpAddress" \
  --output text | tr '\t' '\n' | sort | head -n 1)

# Securely fetch my own private IP via IMDSv2
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
MY_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# 4. Bootstrap or Join
if [ -z "$EXISTING_CP" ] || [ "$EXISTING_CP" == "$MY_IP" ]; then
  echo "I am the designated leader. Initializing HA cluster..."
  curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN sh -s - server \
    --cluster-init \
    --disable-network-policy \
    --flannel-backend=none \
    --write-kubeconfig-mode 644 \
    --cluster-cidr=192.168.0.0/16 \
    --tls-san="${NLB_DNS}"
    
  sleep 20 # Wait for API server
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  # Install Calico (Only the leader needs to execute manifests)
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
  sleep 20

  # Bootstrap ArgoCD
  GITHUB_SECRET_ID="rr-${ENVIRONMENT}-argocd-github-token"
  GITHUB_PAT=$(aws secretsmanager get-secret-value --region $REGION --secret-id $GITHUB_SECRET_ID --query SecretString --output text)

  kubectl create namespace argocd || true
  kubectl create secret generic github-pat --namespace=argocd --from-literal=token=$GITHUB_PAT || true
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

else
  echo "Existing leader found at $EXISTING_CP. Joining HA cluster..."
  sleep 30 # Give the leader a head start to initialize etcd
  curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN sh -s - server \
    --server https://$EXISTING_CP:6443 \
    --disable-network-policy \
    --flannel-backend=none \
    --write-kubeconfig-mode 644 \
    --cluster-cidr=192.168.0.0/16 \
    --tls-san="${NLB_DNS}"
fi