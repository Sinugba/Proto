# FLUX.1-dev + LoRA — AWS Deployment

Deploys **ComfyUI** with **FLUX.1-dev fp8** and the **NSFW_master_ZIT LoRA** on an on-demand EC2 `g5.xlarge` (A10G 24 GB VRAM) via CloudFormation.

ComfyUI runs directly via Python + systemd — no Docker. All models and the Python venv live on a retained EBS volume (`/data`) that survives stack deletion.

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
├── Launch Template         — on-demand, IMDSv2, encrypted root + data volumes
└── EC2 g5.xlarge (on-demand)
    └── UserData bootstrap
        ├── growpart + xfs_growfs (root is XFS, not ext4)
        ├── Python 3.11 install (3.10+ required for comfy-kitchen)
        ├── EBS format + mount at /data
        ├── 20 GB swapfile on /data (unet ~17 GB > 16 GB RAM — mmap needs swap)
        ├── PyTorch venv at /data/venv (keeps root volume free)
        ├── ComfyUI clone at /opt/ComfyUI + symlinks to /data/{models,input,output,custom_nodes}
        ├── ComfyUI Manager clone into /data/custom_nodes/
        ├── HuggingFace model downloads (unet, CLIP, VAE)
        └── systemd comfyui.service (auto-start, restart on failure)
```

### Instance Type

| Type | GPU | VRAM | RAM | On-demand |
|------|-----|------|-----|-----------|
| `g5.xlarge` | A10G | 24 GB | 16 GB | ~$1.006/hr |
| `g6.xlarge` | L4 | 24 GB | 32 GB | ~$0.805/hr |

> **Why on-demand?** Spot instances are terminated without warning, losing any in-progress generation. On-demand is ~$0.006/hr more than peak spot but reliable.

---

## Commands

```bash
./setup.sh --deploy          # Deploy / update stack
./setup.sh --status          # Stack status + ComfyUI URL + SSH command
./setup.sh --connect         # SSH into the instance
./setup.sh --logs            # Tail /var/log/flux-setup.log via SSH
./setup.sh --stop            # Stop instance (EBS + models preserved, compute billing stops)
./setup.sh --start           # Start a stopped instance
./setup.sh --upload-lora     # Upload LoRA file to S3
./setup.sh --teardown        # Delete stack (EBS volume is RETAINED)
```

---

## Getting Models onto the Instance

Models are downloaded automatically on first boot from HuggingFace (~28 GB total, ~15–30 min):

| Model | Source | Size |
|-------|--------|------|
| `flux1-dev-fp8.safetensors` | `Comfy-Org/flux1-dev` | ~17 GB |
| `clip_l.safetensors` | `comfyanonymous/flux_text_encoders` | ~246 MB |
| `t5xxl_fp8_e4m3fn.safetensors` | `comfyanonymous/flux_text_encoders` | ~9.8 GB |
| `ae.safetensors` | `black-forest-labs/FLUX.1-dev` | ~335 MB |

To add the LoRA after deploy:
```bash
./setup.sh --upload-lora     # upload from S3
# or SCP directly:
scp -i ~/.ssh/flux-dev.pem NSFW_master_ZIT_000008766.safetensors \
  ec2-user@<ip>:/data/models/loras/
```

---

## Using ComfyUI After Deploy

1. Run `./setup.sh --status` to get the ComfyUI URL
2. Open `http://<ip>:8188` in your browser
3. Load the workflow: **Load** → select `flux1-dev-lora.json` from `workflows/`
4. The workflow is pre-wired:
   - `UNETLoader` → `flux1-dev-fp8.safetensors` (`fp8_e4m3fn`)
   - `LoraLoader` → `NSFW_master_ZIT_000008766.safetensors` (strength 0.75/0.75)
   - KSampler: steps=20, cfg=3.5, euler, simple

To restart ComfyUI if it dies:
```bash
# If running as systemd service:
sudo systemctl restart comfyui

# If started manually (run in SSH session, survives disconnect):
cd /home/ec2-user/ComfyUI
nohup /data/venv/bin/python main.py --listen 0.0.0.0 --port 8188 \
  > /tmp/comfyui.log 2>&1 &
tail -f /tmp/comfyui.log
```

---

## Cost Breakdown

All prices us-east-1, April 2026.

### When instance is RUNNING

| Resource | Rate | 1 hr | 8 hrs/day × 30 days |
|----------|------|------|----------------------|
| g5.xlarge on-demand | $1.006/hr | $1.01 | $241.44 |
| EBS root 100 GB gp3 | $0.08/GB/mo | — | $8.00 |
| EBS data 150 GB gp3 | $0.08/GB/mo | — | $12.00 |
| Data transfer out | $0.09/GB | ~$0 | ~$0.50 |
| **Total (8 hrs/day)** | | | **~$261/mo** |

### When instance is STOPPED

Compute billing stops immediately when you run `--stop`. Only storage remains:

| Resource | Rate | Per month |
|----------|------|-----------|
| EBS root 100 GB gp3 | $0.08/GB/mo | $8.00 |
| EBS data 150 GB gp3 | $0.08/GB/mo | $12.00 |
| **Total (stopped)** | | **~$20/mo** |

### Typical usage pattern

| Pattern | Estimate |
|---------|----------|
| 2 hrs/day active, stopped otherwise | ~$80/mo |
| 4 hrs/day active, stopped otherwise | ~$141/mo |
| Running 24/7 | ~$743/mo |
| Stopped all month (idle) | ~$20/mo |

> **Key tip:** Always run `./setup.sh --stop` when done. The $20/mo storage cost keeps your 28 GB of downloaded models safe so you don't re-download on next deploy.

---

## Security Notes

- Port 8188 is restricted to `AllowedCidr` — **never open to 0.0.0.0/0** (ComfyUI has no auth)
- IMDSv2 is enforced on the instance (prevents SSRF attacks against metadata service)
- EBS volumes are encrypted at rest
- Root volume is deleted on termination; model volume is retained
- HF token is passed via CloudFormation parameter with `NoEcho: true` — it appears in UserData on the instance; for production use AWS Secrets Manager instead

---

## Troubleshooting

**Setup not complete after 10+ min:**
```bash
./setup.sh --logs
# or SSH in and run:
sudo tail -100 /var/log/flux-setup.log
```

**ComfyUI not reachable:**
- Check your IP hasn't changed: `curl checkip.amazonaws.com` — update `AllowedCidr` if needed
- Check service: `ssh` in, then `sudo systemctl status comfyui`

**Out of memory loading unet (`Cannot allocate memory`):**
```bash
# g5.xlarge has 16 GB RAM but unet is ~17 GB — swap is required
sudo fallocate -l 20G /data/swapfile
sudo chmod 600 /data/swapfile
sudo mkswap /data/swapfile
sudo swapon /data/swapfile
```
New deployments create the swapfile automatically via UserData.

**Root volume full (`No space left on device`):**
```bash
# PyTorch must be installed to /data/venv, not root
# Check what's filling root:
sudo du -sh /opt/conda 2>/dev/null   # AMI conda env — safe to delete
sudo du -sh ~/.local/lib             # partial pip installs — safe to delete
df -h /
```

**`comfy-kitchen` install fails (no matching distribution):**
This means Python 3.9 is being used. The AMI default is 3.9; must use `python3.11`.
New deployments use `python3.11` explicitly throughout.

**`resize2fs` fails on root volume:**
The AMI root filesystem is XFS, not ext4. Use `xfs_growfs /` instead.

**AMI not found in your region:**
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
- `prompts.yaml` — FLUX.1 prompt library with dev ksampler settings
