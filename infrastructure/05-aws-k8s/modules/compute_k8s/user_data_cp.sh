#!/bin/bash
set -e

# 1. System Updates & Prerequisites (AL2023 uses dnf)
dnf update -y
# AWS CLI v2 is pre-installed on AL2023. We just need jq and tar.
dnf install -y jq tar

# 2. Fetch the GitHub PAT for ArgoCD via the NAT Gateway
SECRET_ID="rr-${environment}-argocd-github-token"
REGION="${aws_region}"

# Retrieve secret directly into memory
GITHUB_PAT=$(aws secretsmanager get-secret-value \
  --region $REGION \
  --secret-id $SECRET_ID \
  --query SecretString \
  --output text)

# 3. Bootstrap K3s (Flannel Disabled)
curl -sfL https://get.k3s.io | sh -s - server \
  --disable-network-policy \
  --flannel-backend=none \
  --write-kubeconfig-mode 644 \
  --cluster-cidr=192.168.0.0/16

# Wait for API server to come up
sleep 15
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 4. Install Calico CNI
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# Wait for Calico to initialize
sleep 20

# 5. Bootstrap ArgoCD and Inject the GitOps Token
kubectl create namespace argocd

# Create the native K8s secret containing the PAT
kubectl create secret generic github-pat \
  --namespace=argocd \
  --from-literal=token=$GITHUB_PAT

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml