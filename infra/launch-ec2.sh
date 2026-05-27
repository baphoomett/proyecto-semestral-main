#!/bin/bash
# Launch EC2 instances for Front and Back with AWS CLI using userdata script
# Usage: edit variables below, then run: ./launch-ec2.sh
set -euo pipefail

# --- CONFIGURE THESE ---
AWS_REGION="us-east-1"
AMI_ID="ami-0abcdef1234567890" # Replace with Ubuntu 22.04 AMI for your region
INSTANCE_TYPE="t3.micro"
KEY_NAME="deploy-key"             # Key name to import or use existing
PUBLIC_KEY_PATH="$HOME/.ssh/ec2_deploy_key.pub"  # Local public key to import
VPC_ID=""                         # optional, can be left empty
SUBNET_ID=""                      # optional, can be left empty

# Names and tags
FRONT_SG_NAME="frontend-sg"
BACK_SG_NAME="backend-sg"
FRONT_NAME="front-instance"
BACK_NAME="back-instance"

# File paths
USERDATA_FILE="infra/userdata-docker.sh"

# --- END CONFIG ---

if [ -z "$AMI_ID" ]; then
  echo "Set AMI_ID in the script before running." >&2
  exit 2
fi

export AWS_REGION

echo "Uploading key pair (if not exists)"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region $AWS_REGION >/dev/null 2>&1; then
  echo "Key pair $KEY_NAME already exists. Skipping import."
else
  if [ ! -f "$PUBLIC_KEY_PATH" ]; then
    echo "Public key not found at $PUBLIC_KEY_PATH" >&2
    exit 2
  fi
  aws ec2 import-key-pair --key-name "$KEY_NAME" --public-key-material fileb://$PUBLIC_KEY_PATH --region $AWS_REGION
  echo "Imported key pair $KEY_NAME"
fi

# Create security groups
create_sg(){
  local NAME="$1"; shift
  local DESC="$1"; shift
  VPC_ARG=( )
  if [ -n "$VPC_ID" ]; then VPC_ARG=(--vpc-id "$VPC_ID"); fi
  SG_ID=$(aws ec2 create-security-group --group-name "$NAME" --description "$DESC" "${VPC_ARG[@]}" --region $AWS_REGION --query 'GroupId' --output text)
  echo "$SG_ID"
}

echo "Creating security groups..."
FRONT_SG_ID=$(create_sg "$FRONT_SG_NAME" "Frontend security group")
BACK_SG_ID=$(create_sg "$BACK_SG_NAME" "Backend security group")

echo "Configuring ingress rules..."
# Front: allow HTTP(80), SSH from your IP (replace YOUR_IP/CIDR)
MY_IP_CIDR="0.0.0.0/0" # TODO: change to your IP like 1.2.3.4/32
aws ec2 authorize-security-group-ingress --group-id $FRONT_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $AWS_REGION || true
aws ec2 authorize-security-group-ingress --group-id $FRONT_SG_ID --protocol tcp --port 22 --cidr $MY_IP_CIDR --region $AWS_REGION || true

# Back: allow app ports from frontend SG, allow SSH from your IP
aws ec2 authorize-security-group-ingress --group-id $BACK_SG_ID --protocol tcp --port 8080 --source-group $FRONT_SG_ID --region $AWS_REGION || true
aws ec2 authorize-security-group-ingress --group-id $BACK_SG_ID --protocol tcp --port 8081 --source-group $FRONT_SG_ID --region $AWS_REGION || true
aws ec2 authorize-security-group-ingress --group-id $BACK_SG_ID --protocol tcp --port 22 --cidr $MY_IP_CIDR --region $AWS_REGION || true

# Launch function
launch_instance(){
  local NAME="$1"; shift
  local SG_ID="$1"; shift
  local TAG="$1"; shift
  local INSTANCE_ID
  echo "Launching $NAME..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    ${SUBNET_ID:+--subnet-id $SUBNET_ID} \
    --associate-public-ip-address \
    --user-data file://$USERDATA_FILE \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TAG}]" \
    --region $AWS_REGION \
    --query 'Instances[0].InstanceId' --output text)
  echo "$INSTANCE_ID"
}

FRONT_INSTANCE_ID=$(launch_instance "$FRONT_NAME" $FRONT_SG_ID $FRONT_NAME)
BACK_INSTANCE_ID=$(launch_instance "$BACK_NAME" $BACK_SG_ID $BACK_NAME)

echo "Waiting for instances to be running..."
aws ec2 wait instance-running --instance-ids $FRONT_INSTANCE_ID $BACK_INSTANCE_ID --region $AWS_REGION

# Allocate and associate Elastic IPs
FRONT_EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region $AWS_REGION --query 'AllocationId' --output text)
BACK_EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --region $AWS_REGION --query 'AllocationId' --output text)

FRONT_EIP_ASSOC=$(aws ec2 associate-address --instance-id $FRONT_INSTANCE_ID --allocation-id $FRONT_EIP_ALLOC_ID --region $AWS_REGION --query 'AssociationId' --output text)
BACK_EIP_ASSOC=$(aws ec2 associate-address --instance-id $BACK_INSTANCE_ID --allocation-id $BACK_EIP_ALLOC_ID --region $AWS_REGION --query 'AssociationId' --output text)

FRONT_PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids $FRONT_EIP_ALLOC_ID --region $AWS_REGION --query 'Addresses[0].PublicIp' --output text)
BACK_PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids $BACK_EIP_ALLOC_ID --region $AWS_REGION --query 'Addresses[0].PublicIp' --output text)

cat <<EOF
Launched instances:
 Front: $FRONT_INSTANCE_ID -> $FRONT_PUBLIC_IP
 Back:  $BACK_INSTANCE_ID -> $BACK_PUBLIC_IP
User: use key $KEY_NAME (private key on your machine) to SSH: ssh -i ~/ec2_deploy_key ubuntu@<IP> or deploy@<IP>
EOF

