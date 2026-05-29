#!/bin/bash
set -e

# 1. System Updates & Prerequisites
dnf update -y
dnf install -y jq tar

REGION="${aws_region}"
ENVIRONMENT="${environment}"

# 2. Discover the Control Plane IP 
# Using the AWS CLI to query the EC2 API for the active Control Plane instance
echo "Locating Control Plane IP..."
CP_IP=""
while [ -z "$CP_IP" ]; do
  CP_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=rr-${ENVIRONMENT}-k3s-control-plane" "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].PrivateIpAddress" \
    --output text)
  
  if [ -z "$CP_IP" ]; then
    echo "Control plane not ready yet. Retrying in 10 seconds..."
    sleep 10
  fi
done

echo "Control Plane found at: $CP_IP"

# 3. Fetch the K3s Cluster Join Token
# [AUTOMATION INJECTION POINT: We will insert the Secrets Manager, S3, or SSM command here]
CLUSTER_TOKEN="TBD" 

# 4. Join the K3s Cluster
# Execute the installation script, instructing it to run as a worker agent
curl -sfL https://get.k3s.io | K3S_URL=https://${CP_IP}:6443 K3S_TOKEN=${CLUSTER_TOKEN} sh -s - agent