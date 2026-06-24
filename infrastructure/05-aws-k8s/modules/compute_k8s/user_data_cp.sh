#!/bin/bash
set -e

# =========================================================================
# 1. SYSTEM UPDATES & PREREQUISITES
# =========================================================================
dnf update -y
dnf install -y jq tar openssl

# Install Helm CLI natively on the host OS
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Variables injected dynamically via Terraform interpolation
REGION="${aws_region}"
ENVIRONMENT="${environment}"
NLB_DNS="${nlb_dns_name}"

# =========================================================================
# 2. FETCH CLUSTER JOIN TOKEN FROM SECRETS MANAGER
# =========================================================================
TOKEN_SECRET_ID="rr-$ENVIRONMENT-k3s-join-token"
K3S_TOKEN=$(aws secretsmanager get-secret-value --region $REGION --secret-id $TOKEN_SECRET_ID --query SecretString --output text)

# =========================================================================
# 3. HIGH-AVAILABILITY LEADER ELECTION (EMBEDDED ETCD)
# =========================================================================
EXISTING_CP=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:Name,Values=rr-$ENVIRONMENT-k3s-control-plane" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PrivateIpAddress" \
  --output text | tr '\t' '\n' | sort | head -n 1)

# Fetch current instance private IP via IMDSv2 token authentication
IMDS_TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
MY_IP=$(curl -sH "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# =========================================================================
# 4. CLUSTER INITIALIZATION OR JOIN ORCHESTRATION
# =========================================================================
if [ -z "$EXISTING_CP" ] || [ "$EXISTING_CP" == "$MY_IP" ]; then
  echo "Designated cluster leader state matched. Initializing database cluster root..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.15+k3s1" K3S_TOKEN=$K3S_TOKEN sh -s - server \
    --cluster-init \
    --disable-network-policy \
    --disable traefik \
    --flannel-backend=none \
    --write-kubeconfig-mode 644 \
    --cluster-cidr=192.168.0.0/16 \
    --tls-san="$NLB_DNS"
    
  sleep 20
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

  # Deploy Calico operator and custom infrastructure manifests
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
  sleep 20

  # =========================================================================
  # 5. BOOTSTRAP ARGOCD VIA HELM (FIXES METADATA LIMIT OVERFLOW)
  # =========================================================================
  kubectl create namespace argocd || true
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm install argocd argo/argo-cd -n argocd --set server.service.type=ClusterIP

  # Fetch Personal Access Token from AWS Secrets Manager
  GITHUB_SECRET_ID="rr-$ENVIRONMENT-argocd-github-token"
  GITHUB_PAT=$(aws secretsmanager get-secret-value --region $REGION --secret-id $GITHUB_SECRET_ID --query SecretString --output text)

  # Explicitly structure and label the secret so ArgoCD matches it to the private repo
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ritual-roast-git-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/ManunEbo/Terraform-AWS-Ritual-Roast-Part-2-Containerised.git
  password: $GITHUB_PAT
EOF

  # Deploy secure container registry mapping secret inside target runtime namespace
  kubectl create namespace dev || true
  # Enrol the dev namespace in the mesh so every pod gets an Envoy sidecar (2/2).
  # Idempotent: --overwrite is a no-op if the label is already present.
  kubectl label namespace dev istio-injection=enabled --overwrite || true
  kubectl create secret docker-registry ghcr-login-secret \
    --namespace=dev \
    --docker-server=ghcr.io \
    --docker-username=ManunEbo \
    --docker-password=$GITHUB_PAT || true

  # =========================================================================
  # INFRASTRUCTURE HANDOFF: Pass the exact Secret ARN to the Dev namespace
  # =========================================================================
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: dev
data:
  SECRET_ARN: "${DB_SECRET_ARN}"
  AWS_REGION: "$REGION"
EOF
  
  # =========================================================================
  # 6. BOOTSTRAP OBSERVABILITY CREDENTIALS
  # =========================================================================
  GRAFANA_SECRET_ID="rr-$ENVIRONMENT-grafana-cloud-token"
  GRAFANA_TOKEN=$(aws secretsmanager get-secret-value --region $REGION --secret-id $GRAFANA_SECRET_ID --query SecretString --output text)

  kubectl create namespace observability || true
  kubectl create secret generic grafana-auth \
    --namespace=observability \
    --from-literal=bearer-token=$GRAFANA_TOKEN || true

  # =========================================================================
  # 7. IGNITE GITOPS HANDOVER
  # =========================================================================
  echo "Awaiting custom resource definition stabilization..."
  until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do 
    sleep 5
  done

  echo "Injecting Root Application Controllers..."
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
EOF

else
  echo "Active environment leader discovered at $EXISTING_CP. Executing cluster join link..."
  sleep 30 
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.15+k3s1" K3S_TOKEN=$K3S_TOKEN sh -s - server \
    --server https://$EXISTING_CP:6443 \
    --disable-network-policy \
    --disable traefik \
    --flannel-backend=none \
    --write-kubeconfig-mode 644 \
    --cluster-cidr=192.168.0.0/16 \
    --tls-san="$NLB_DNS"
fi