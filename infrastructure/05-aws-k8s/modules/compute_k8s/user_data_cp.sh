#!/bin/bash
set -e

# 1. System Updates & Prerequisites
dnf update -y
dnf install -y jq tar openssl
# Add Helm install here
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Terraform strictly injects these values here
REGION="${aws_region}"
ENVIRONMENT="${environment}"
NLB_DNS="${nlb_dns_name}"

# 2. Fetch the K3s Cluster Join Token 
# (Curly braces removed so Terraform ignores this bash variable)
TOKEN_SECRET_ID="rr-$ENVIRONMENT-k3s-join-token"
K3S_TOKEN=$(aws secretsmanager get-secret-value --region $REGION --secret-id $TOKEN_SECRET_ID --query SecretString --output text)

# 3. HA Leader Election (Embedded etcd)
EXISTING_CP=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:Name,Values=rr-$ENVIRONMENT-k3s-control-plane" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PrivateIpAddress" \
  --output text | tr '\t' '\n' | sort | head -n 1)

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
MY_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# 4. Bootstrap or Join
if [ -z "$EXISTING_CP" ] || [ "$EXISTING_CP" == "$MY_IP" ]; then
  echo "I am the designated leader. Initializing HA cluster..."
  curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN sh -s - server \
    --cluster-init \
    --disable-network-policy \
    --disable traefik \
    --flannel-backend=none \
    --write-kubeconfig-mode 644 \
    --cluster-cidr=192.168.0.0/16 \
    --tls-san="$NLB_DNS"
    
  sleep 20 # Wait for API server
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  # Install Calico
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
  sleep 20

# 5. Bootstrap ArgoCD via Helm (The reproducible way)
  kubectl create namespace argocd || true
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm install argocd argo/argo-cd -n argocd --set server.service.type=ClusterIP

  # Inject GHCR login secret
  GITHUB_SECRET_ID="rr-$ENVIRONMENT-argocd-github-token"
  GITHUB_PAT=$(aws secretsmanager get-secret-value --region $REGION --secret-id $GITHUB_SECRET_ID --query SecretString --output text)
  
  kubectl create secret generic github-pat --namespace=argocd --from-literal=token=$GITHUB_PAT || true
  kubectl create secret docker-registry ghcr-login-secret \
    --namespace=dev \
    --docker-server=ghcr.io \
    --docker-username=ManunEbo \
    --docker-password=$GITHUB_PAT || true

  # 6. Bootstrap Observability Credentials for GitOps
  echo "Staging Grafana Cloud credentials..."
  GRAFANA_SECRET_ID="rr-$ENVIRONMENT-grafana-cloud-token"
  GRAFANA_TOKEN=$(aws secretsmanager get-secret-value --region $REGION --secret-id $GRAFANA_SECRET_ID --query SecretString --output text)

  kubectl create namespace observability || true
  kubectl create secret generic grafana-auth \
    --namespace=observability \
    --from-literal=bearer-token=$GRAFANA_TOKEN || true

  # =========================================================================
  # 7. IGNITE GITOPS (THE HANDOVER)
  # =========================================================================
  echo "Waiting for ArgoCD CRDs to register in the cluster..."
  until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do sleep 5; echo "Waiting..."; done

  echo "Injecting Root ArgoCD Applications..."
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-observability
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised.git'
    targetRevision: main
    path: infrastructure/05-aws-k8s/k8s-manifests/observability
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: observability
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-dev-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised.git'
    targetRevision: main
    path: infrastructure/05-aws-k8s/k8s-manifests/dev-apps
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

else
  echo "Existing leader found at $EXISTING_CP. Joining HA cluster..."
  sleep 30 
  curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN sh -s - server \
    --server https://$EXISTING_CP:6443 \
    --disable-network-policy \
    --disable traefik \
    --flannel-backend=none \
    --write-kubeconfig-mode 644 \
    --cluster-cidr=192.168.0.0/16 \
    --tls-san="$NLB_DNS"
fi