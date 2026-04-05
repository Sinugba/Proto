#!/usr/bin/env bash
# =============================================================================
# setup.sh — Deploy FLUX.1-dev + LoRA ComfyUI stack to AWS
#
# Prerequisites (run once before this script):
#   1. AWS CLI v2 installed and configured:  aws configure
#   2. An EC2 Key Pair created in your target region
#   3. Your public IP (https://checkip.amazonaws.com)
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh                        # interactive — prompts for all values
#   ./setup.sh --deploy               # deploy with values in config section
#   ./setup.sh --status               # check stack/instance status
#   ./setup.sh --connect              # SSH into the instance
#   ./setup.sh --logs                 # tail the setup log via SSM
#   ./setup.sh --stop                 # stop instance (preserves EBS + models)
#   ./setup.sh --start                # start a stopped instance
#   ./setup.sh --teardown             # DELETE stack (EBS volume is retained)
#
# =============================================================================
set -euo pipefail

# =============================================================================
# CONFIGURATION — edit these before running --deploy
# =============================================================================

STACK_NAME="flux1-dev-comfyui"
REGION="us-east-1"
INSTANCE_TYPE="g5.xlarge"           # A10G 24 GB — recommended
AVAILABILITY_ZONE="us-east-1b"      # g5.xlarge unavailable in us-east-1a; use 1b/1c/1d/1f
KEY_PAIR_NAME="flux-dev"              # EC2 key pair name — ~/.ssh/flux-dev.pem must exist locally
ALLOWED_CIDR="165.171.157.165/32"    # Your IP: e.g. 203.0.113.5/32
SPOT_MAX_PRICE="0.50"
EBS_VOLUME_SIZE="150"
HF_TOKEN=""                          # HuggingFace token — leave blank to be prompted at deploy time
S3_BUCKET_NAME="flux1-dev"                    # S3 bucket containing the LoRA file

# Local path for --upload-lora
PROTO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LORA_FILE="$PROTO_ROOT/models/loras/NSFW_master_ZIT_000008766.safetensors"
CFN_TEMPLATE="$(dirname "$0")/cloudformation.yaml"

# =============================================================================
# Helpers
# =============================================================================

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || error "$1 is not installed. $2"; }
require_config() {
    local val="$1" name="$2"
    [[ -n "$val" ]] || error "$name is not set. Edit the CONFIGURATION section in setup.sh or pass it as an argument."
}

get_instance_id() {
    aws cloudformation describe-stack-resource \
        --stack-name "$STACK_NAME" \
        --logical-resource-id Instance \
        --region "$REGION" \
        --query "StackResourceDetail.PhysicalResourceId" \
        --output text 2>/dev/null || true
}

get_public_ip() {
    local iid="$1"
    aws ec2 describe-instances \
        --instance-ids "$iid" \
        --region "$REGION" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text 2>/dev/null || true
}

# =============================================================================
# Actions
# =============================================================================

cmd_check_prereqs() {
    info "Checking prerequisites..."
    require_cmd aws  "Install from https://aws.amazon.com/cli/"
    require_cmd jq   "Install: brew install jq  (macOS)  or  sudo apt install jq  (Linux)"
    aws sts get-caller-identity --region "$REGION" --output table \
        || error "AWS CLI not configured. Run: aws configure"
    success "Prerequisites OK"
}

cmd_interactive() {
    echo ""
    echo "=============================================="
    echo " FLUX.1-dev ComfyUI — AWS Deployment Setup"
    echo "=============================================="
    echo ""

    read -rp "AWS Region [$REGION]: " inp; REGION="${inp:-$REGION}"
    read -rp "Stack name [$STACK_NAME]: " inp; STACK_NAME="${inp:-$STACK_NAME}"
    read -rp "EC2 Key Pair name: " inp; KEY_PAIR_NAME="${inp:-$KEY_PAIR_NAME}"
    read -rp "Your IP CIDR (e.g. 1.2.3.4/32): " inp; ALLOWED_CIDR="${inp:-$ALLOWED_CIDR}"
    read -rp "Instance type [$INSTANCE_TYPE]: " inp; INSTANCE_TYPE="${inp:-$INSTANCE_TYPE}"
    read -rp "Availability Zone [$AVAILABILITY_ZONE]: " inp; AVAILABILITY_ZONE="${inp:-$AVAILABILITY_ZONE}"
    read -rp "Spot max price USD/hr [$SPOT_MAX_PRICE]: " inp; SPOT_MAX_PRICE="${inp:-$SPOT_MAX_PRICE}"
    read -rp "EBS volume size GB [$EBS_VOLUME_SIZE]: " inp; EBS_VOLUME_SIZE="${inp:-$EBS_VOLUME_SIZE}"
    read -rsp "HuggingFace token (hidden, REQUIRED): " inp; HF_TOKEN="${inp:-$HF_TOKEN}"; echo ""
    read -rp "S3 bucket name for LoRA (leave blank to upload manually later): " inp; S3_BUCKET_NAME="${inp:-$S3_BUCKET_NAME}"

    echo ""
    cmd_deploy
}

cmd_deploy() {
    cmd_check_prereqs
    require_config "$KEY_PAIR_NAME"  "KEY_PAIR_NAME"
    require_config "$ALLOWED_CIDR"   "ALLOWED_CIDR"
    if [[ -z "$HF_TOKEN" ]]; then
        read -rsp "HuggingFace token (hidden, REQUIRED): " HF_TOKEN; echo ""
        [[ -n "$HF_TOKEN" ]] || error "HF_TOKEN is required to download models."
    fi

    info "Validating CloudFormation template..."
    aws cloudformation validate-template \
        --template-body "file://$CFN_TEMPLATE" \
        --region "$REGION" \
        --output table

    # Build parameter list
    PARAMS=(
        "ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR_NAME"
        "ParameterKey=AllowedCidr,ParameterValue=$ALLOWED_CIDR"
        "ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE"
        "ParameterKey=AvailabilityZone,ParameterValue=$AVAILABILITY_ZONE"
        "ParameterKey=SpotMaxPrice,ParameterValue=$SPOT_MAX_PRICE"
        "ParameterKey=EbsVolumeSize,ParameterValue=$EBS_VOLUME_SIZE"
    )
    [[ -n "$HF_TOKEN"       ]] && PARAMS+=("ParameterKey=HfToken,ParameterValue=$HF_TOKEN")
    [[ -n "$S3_BUCKET_NAME" ]] && PARAMS+=("ParameterKey=ModelsBucketName,ParameterValue=$S3_BUCKET_NAME")

    # Deploy (create or update)
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "DOES_NOT_EXIST")

    if [[ "$STACK_STATUS" == "DOES_NOT_EXIST" ]]; then
        info "Creating stack: $STACK_NAME ..."
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$CFN_TEMPLATE" \
            --parameters "${PARAMS[@]}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$REGION"
        info "Waiting for stack creation (this takes 3-5 minutes)..."
        aws cloudformation wait stack-create-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION"
    else
        warn "Stack $STACK_NAME exists (status: $STACK_STATUS). Updating..."
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$CFN_TEMPLATE" \
            --parameters "${PARAMS[@]}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$REGION" || warn "No changes to deploy."
        aws cloudformation wait stack-update-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION" 2>/dev/null || true
    fi

    cmd_status
}

cmd_upload_lora() {
    require_config "$S3_BUCKET_NAME" "S3_BUCKET_NAME"
    [[ -f "$LORA_FILE" ]] || error "LoRA not found at: $LORA_FILE"
    info "Uploading LoRA to s3://$S3_BUCKET_NAME/models/loras/..."
    aws s3 cp "$LORA_FILE" \
        "s3://$S3_BUCKET_NAME/models/loras/$(basename "$LORA_FILE")" \
        --region "$REGION"
    success "LoRA uploaded."
}

cmd_status() {
    info "Stack status:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].{Status:StackStatus,Created:CreationTime}" \
        --output table 2>/dev/null || warn "Stack not found."

    INSTANCE_ID="$(get_instance_id)"
    if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" ]]; then
        info "Instance: $INSTANCE_ID"
        aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --region "$REGION" \
            --query "Reservations[0].Instances[0].{State:State.Name,IP:PublicIpAddress,Type:InstanceType,AZ:Placement.AvailabilityZone}" \
            --output table

        PUBLIC_IP="$(get_public_ip "$INSTANCE_ID")"
        if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
            success "ComfyUI: http://$PUBLIC_IP:8188"
            success "SSH:     ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ec2-user@$PUBLIC_IP"
            info    "Setup log: ssh in, then run: sudo tail -f /var/log/flux-setup.log"
        fi
    fi

    echo ""
    info "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs" \
        --output table 2>/dev/null || true
}

cmd_connect() {
    require_config "$KEY_PAIR_NAME" "KEY_PAIR_NAME"
    INSTANCE_ID="$(get_instance_id)"
    [[ -n "$INSTANCE_ID" ]] || error "No instance found. Deploy first with: ./setup.sh --deploy"
    PUBLIC_IP="$(get_public_ip "$INSTANCE_ID")"
    [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]] || error "Instance has no public IP (may be stopped)."
    info "Connecting to $PUBLIC_IP..."
    ssh -i "$HOME/.ssh/${KEY_PAIR_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        "ec2-user@$PUBLIC_IP"
}

cmd_logs() {
    INSTANCE_ID="$(get_instance_id)"
    [[ -n "$INSTANCE_ID" ]] || error "No instance found."
    info "Tailing /var/log/flux-setup.log via SSM (Ctrl+C to stop)..."
    aws ssm start-session \
        --target "$INSTANCE_ID" \
        --region "$REGION" \
        --document-name AWS-StartInteractiveCommand \
        --parameters '{"command":["sudo tail -f /var/log/flux-setup.log"]}'
}

cmd_stop() {
    INSTANCE_ID="$(get_instance_id)"
    [[ -n "$INSTANCE_ID" ]] || error "No instance found."
    info "Stopping instance $INSTANCE_ID (EBS volume and models are preserved)..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output table
    success "Instance stopping. Models on EBS are safe."
}

cmd_start() {
    INSTANCE_ID="$(get_instance_id)"
    [[ -n "$INSTANCE_ID" ]] || error "No instance found."
    info "Starting instance $INSTANCE_ID..."
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output table
    info "Waiting for instance to reach running state..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
    PUBLIC_IP="$(get_public_ip "$INSTANCE_ID")"
    success "Instance running. ComfyUI: http://$PUBLIC_IP:8188"
    warn "Note: spot instances get a NEW public IP on start. Update your browser URL."
}

cmd_teardown() {
    warn "This will DELETE the CloudFormation stack and all resources EXCEPT the EBS volume."
    warn "Stack: $STACK_NAME  |  Region: $REGION"
    read -rp "Type the stack name to confirm deletion: " confirm
    [[ "$confirm" == "$STACK_NAME" ]] || { info "Aborted."; exit 0; }

    VOLUME_ID=$(aws cloudformation describe-stack-resource \
        --stack-name "$STACK_NAME" \
        --logical-resource-id ModelsVolume \
        --region "$REGION" \
        --query "StackResourceDetail.PhysicalResourceId" \
        --output text 2>/dev/null || true)

    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
    info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    success "Stack deleted."

    if [[ -n "$VOLUME_ID" && "$VOLUME_ID" != "None" ]]; then
        success "EBS volume retained: $VOLUME_ID (contains your models)"
        info    "To permanently delete it: aws ec2 delete-volume --volume-id $VOLUME_ID --region $REGION"
    fi
}

# =============================================================================
# Entrypoint
# =============================================================================

usage() {
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "  (no args)          Interactive setup wizard"
    echo "  --deploy           Deploy using values in the CONFIGURATION section"
  echo "  --upload-lora      Upload LoRA file to S3 bucket"
    echo "  --status           Show stack, instance, and ComfyUI URL"
    echo "  --connect          SSH into the instance"
    echo "  --logs             Tail the setup log via SSM"
    echo "  --stop             Stop the instance (preserves EBS + models)"
    echo "  --start            Start a previously stopped instance"
    echo "  --teardown         Delete the stack (EBS volume is retained)"
    echo "  --help             Show this help"
    echo ""
}

case "${1:-}" in
    --deploy)         cmd_deploy ;;
    --upload-lora)    cmd_upload_lora ;;
    --status)         cmd_status ;;
    --connect)        cmd_connect ;;
    --logs)           cmd_logs ;;
    --stop)           cmd_stop ;;
    --start)          cmd_start ;;
    --teardown)       cmd_teardown ;;
    --help|-h)        usage ;;
    "")               cmd_interactive ;;
    *)                error "Unknown option: $1"; usage ;;
esac
