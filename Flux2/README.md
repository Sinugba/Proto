# FLUX.1-dev + LoRA — AWS Deployment

Deploys **ComfyUI** with **FLUX.1-dev fp8** and the **NSFW_master_ZIT LoRA** on a spot EC2 `g5.xlarge` (A10G 24 GB VRAM) via CloudFormation.

Builds on the same Docker image used locally in `Proto/` — no code changes required between local and cloud.

---

## Prerequisites

| Tool | Install |
|------|---------|
| AWS CLI v2 | https://aws.amazon.com/cli/ |
| `jq` | `brew install jq` / `sudo apt install jq` |
| Configured AWS credentials | `aws configure` |
| EC2 Key Pair | AWS Console → EC2 → Key Pairs → Create |

---

## Quick Start

```bash
cd Generators/Flux2
chmod +x setup.sh

# Interactive wizard — prompts for all values
./setup.sh
```

Or edit the `CONFIGURATION` section at the top of `setup.sh` and run:

```bash
./setup.sh --deploy
```

---

## Required Configuration

Edit these values in `setup.sh` before deploying:

```bash
REGION="us-east-1"             # AWS region
KEY_PAIR_NAME="my-key"         # EC2 key pair name (no .pem)
ALLOWED_CIDR="1.2.3.4/32"     # Your IP — find it at https://checkip.amazonaws.com
HF_TOKEN="hf_xxx"             # HuggingFace token (for ae.safetensors VAE download)
```

---

## What Gets Created

```
CloudFormation Stack
├── VPC + public subnet + internet gateway + route table
├── Security Group          — port 22 + 8188 restricted to your IP only
├── IAM Role + Profile      — EC2 → S3 read (if bucket used) + SSM Session Manager
├── EBS gp3 volume (150 GB) — DeletionPolicy: Retain (survives stack delete)
├── Launch Template         — spot, IMDSv2, encrypted root + data volumes
└── EC2 g5.xlarge (spot)
    └── UserData bootstrap
        ├── NVIDIA driver check
        ├── Docker + NVIDIA Container Toolkit
        ├── EBS format + mount at /data
        ├── ComfyUI-GGUF custom node clone
        ├── docker-compose.yaml + Dockerfile write
        └── docker compose build + up
```

### Instance Type Options

| Type | GPU | VRAM | On-demand | Spot est. | `--lowvram`? |
|------|-----|------|-----------|-----------|--------------|
| `g5.xlarge` | A10G | 24 GB | ~$1.01/hr | ~$0.35/hr | No — recommended |
| `g6.xlarge` | L4 | 24 GB | ~$0.80/hr | ~$0.28/hr | No |
| `g4dn.xlarge` | T4 | 16 GB | ~$0.53/hr | ~$0.16/hr | Yes (auto-set) |

---

## Commands

```bash
./setup.sh                   # Interactive setup wizard
./setup.sh --deploy          # Deploy / update stack
./setup.sh --status          # Stack status + ComfyUI URL + SSH command
./setup.sh --connect         # SSH into the instance
./setup.sh --logs            # Tail /var/log/flux-setup.log via SSM
./setup.sh --stop            # Stop instance (EBS + models preserved, billing stops)
./setup.sh --start           # Start a stopped instance
./setup.sh --upload-models   # Sync Proto/models/ to S3 (optional, faster first boot)
./setup.sh --upload-lora     # Upload LoRA file to S3
./setup.sh --teardown        # Delete stack (EBS volume is RETAINED)
```

---

## Getting Models onto the Instance

### Option A — Download on first boot (simplest)
The UserData script runs `setup.sh -IncludeDev` equivalent on the instance, downloading all models (~28 GB) from HuggingFace. Takes ~15-30 min depending on region.

Pass your HF token so the gated VAE downloads automatically:
```bash
HF_TOKEN="hf_xxx" ./setup.sh --deploy
```

### Option B — Pre-upload to S3 (faster repeated deployments)
```bash
# Set S3_BUCKET_NAME in setup.sh, then:
./setup.sh --upload-models    # ~28 GB sync — run once
./setup.sh --upload-lora      # uploads NSFW_master_ZIT LoRA

# Future deployments pull from S3 at ~500 MB/s on EC2 — much faster than HF
```

### Option C — SCP directly after deploy
```bash
scp -i ~/.ssh/<key>.pem \
  Proto/models/loras/NSFW_master_ZIT_000008766.safetensors \
  ec2-user@<ip>:/data/models/loras/
```

---

## Using ComfyUI After Deploy

1. Run `./setup.sh --status` to get the ComfyUI URL
2. Open `http://<ip>:8188` in your browser
3. Load the workflow: **Load** → select `flux1-dev-lora.json` from `Proto/workflows/`
4. The workflow is pre-wired:
   - `UNETLoader` → `flux1-dev-fp8-e4m3fn.safetensors` (`fp8_e4m3fn`)
   - `LoraLoader` → `NSFW_master_ZIT_000008766.safetensors` (strength 0.75/0.75)
   - KSampler: steps=20, cfg=3.5, euler, simple

---

## Cost Management

**Stop the instance when not in use** — EBS volume continues to accrue ~$0.40/day but compute billing stops:
```bash
./setup.sh --stop    # stops instance, keeps models safe
./setup.sh --start   # resumes in ~60 seconds
```

**Spot instance note:** The instance will have a different public IP each time it starts. Run `--status` to get the current IP.

**Estimated cost at 2 hrs/day active:**

| | Compute | EBS | Total/month |
|--|---------|-----|-------------|
| g5.xlarge spot | ~$21 | ~$12 | ~$33 |
| g4dn.xlarge spot | ~$10 | ~$12 | ~$22 |

---

## Security Notes

- Port 8188 is restricted to `AllowedCidr` — **never open to 0.0.0.0/0** (ComfyUI has no auth)
- IMDSv2 is enforced on the instance (prevents SSRF attacks against metadata service)
- EBS volumes are encrypted at rest
- Root volume is deleted on termination; model volume is retained
- HF token (if provided) is passed via CloudFormation parameter with `NoEcho: true` — it appears in UserData on the instance; for production use AWS Secrets Manager instead

---

## Troubleshooting

**Setup not complete after 10+ min:**
```bash
./setup.sh --logs    # tail UserData log via SSM
# or SSH in and run:
sudo tail -100 /var/log/flux-setup.log
```

**ComfyUI not reachable:**
- Check your IP hasn't changed: `curl checkip.amazonaws.com` — update `AllowedCidr` if needed
- Check container: `ssh` in, then `docker ps` and `docker compose logs -f`

**Spot instance terminated:**
```bash
./setup.sh --start   # creates a new spot instance, re-attaches the EBS volume
# Models are safe on the retained EBS volume
```

**AMI not found in your region:**
Update the `RegionAMI` mapping in `cloudformation.yaml`:
```bash
aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=Deep Learning Base OSS Nvidia Driver GPU AMI (Amazon Linux 2023)*" \
  --query "sort_by(Images,&CreationDate)[-1].{ID:ImageId,Name:Name}" \
  --output table \
  --region <your-region>
```

---

## Files

```
Flux2/
├── cloudformation.yaml   CloudFormation template (VPC, EC2, EBS, IAM, SG)
├── setup.sh              Deployment script with all management commands
└── README.md             This file
```

Related files in `Proto/`:
- `workflows/flux1-dev-lora.json` — ComfyUI workflow (UNETLoader + LoraLoader)
- `Dockerfile` — bakes gguf pip package into ComfyUI venv
- `docker-compose.yaml` — ComfyUI service definition
- `prompts.yaml` — FLUX.1 prompt library with dev ksampler settings
