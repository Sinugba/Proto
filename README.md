# Running Pony Diffusion V6 (XL) with Docker

This guide provides step-by-step instructions on how to run the Pony Diffusion V6 (XL) model locally using Docker, ComfyUI, and the `ai-dock/comfyui` image.

## Prerequisites

- **NVIDIA GPU** with up-to-date drivers installed.
- **NVIDIA Container Toolkit** to allow Docker containers to access your GPU:
  [https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- **Docker and Docker Compose** installed on your system.
- A **GitHub account** to authenticate with the GitHub Container Registry (`ghcr.io`).

---

## Step 1: Download the Pony Diffusion V6 XL Model

1. Download the model from Civitai:
   [https://civitai.com/models/257749/pony-diffusion-v6-xl](https://civitai.com/models/257749/pony-diffusion-v6-xl)
   - The correct file is named `ponyDiffusionV6XL_v6StartWithThisOne.safetensors` (~6GB).

2. Create the following directory structure next to your `docker-compose.yaml`:

```
.
├── docker-compose.yaml
├── models/
│   └── checkpoints/
│       └── ponyDiffusionV6XL_v6StartWithThisOne.safetensors
├── input/
└── output/
```

---

## Step 2: Docker Compose Configuration

The `docker-compose.yaml` in this repository is already configured correctly:

```yaml
version: '3.8'
services:
  comfyui:
    image: ghcr.io/ai-dock/comfyui:latest-cuda
    runtime: nvidia
    ports:
      - "1111:1111"
      - "8188:8188"
    volumes:
      - ./models:/opt/ComfyUI/models
      - ./input:/opt/ComfyUI/input
      - ./output:/opt/ComfyUI/output
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - WEB_AUTHENTICATION=false
      - WEB_USER=user
      - WEB_PASSWORD=password
```

**Key notes:**
- The image is sourced from `ghcr.io` (GitHub Container Registry) — no Docker Hub rate limits.
- Models are mounted to `/opt/ComfyUI/models` — the correct path for this image.
- Port `1111` is the service portal. Port `8188` is direct ComfyUI access.
- `WEB_AUTHENTICATION=false` disables the login requirement for the portal.

---

## Step 3: Log in to GitHub Container Registry

The image is hosted on `ghcr.io` and requires a GitHub Personal Access Token (PAT) to pull.

### Create a GitHub PAT

1. Go to: [https://github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)
2. Click **Generate new token** and give it a name (e.g., `Docker GHCR`).
3. Under **Permissions → Packages**, grant **Read** access.
4. Click **Generate token** and copy it immediately — you won't see it again.

### Log in via Docker

```bash
docker login ghcr.io
```

- **Username:** your GitHub username
- **Password:** the PAT you just created

---

## Step 4: Start the Container

```bash
docker-compose up -d
```

Check startup logs:

```bash
docker-compose logs -f
```

The container is ready when you see ComfyUI startup messages in the logs. The `ai-dock` image also provides a Cloudflare Quick Tunnel URL in the logs, which lets you access ComfyUI from any device:

```
https://<random-name>.trycloudflare.com
```

---

## Step 5: Access the Service Portal

Open your browser and go to:

[http://localhost:1111](http://localhost:1111)

You will see a portal with the following services:

| Port | Service | Description |
|------|---------|-------------|
| 1111 | Service Portal | Overview of all services |
| 8188 | **ComfyUI** | Image generation interface |
| 8384 | Syncthing | File sync (optional) |
| 8888 | Jupyter Notebook | Python environment (optional) |

Click **8188 → ComfyUI → Direct Link** to open the ComfyUI interface.

---

## Step 6: Load the Model and Generate an Image

1. In ComfyUI, locate the **Load Checkpoint** node (top-left of the default graph).
2. Click the dropdown and select `ponyDiffusionV6XL_v6StartWithThisOne.safetensors`.
   - If the dropdown is empty, press **Ctrl+Shift+D** to reload the default workflow.
3. Find the two **CLIP Text Encode** nodes:
   - **Positive prompt** (top input of KSampler) — enter your prompt tags here.
   - **Negative prompt** (bottom input of KSampler) — enter what to avoid here.
4. Click **Queue Prompt** to generate.
5. Watch the progress bar at the top. Once complete, the image appears in the **Save Image** node and is saved to your local `output/` folder.

---

## Prompting Guide for Pony Diffusion V6 XL

Pony Diffusion uses special quality tags that must be included at the start of your prompt for best results.

### Positive Prompt Structure

```
score_9, score_8_up, score_7_up, <your subject and style tags>, masterpiece, high quality
```

### Quality Tags

| Tag | Meaning |
|-----|---------|
| `score_9` | Highest quality tier |
| `score_8_up` | High quality and above |
| `score_7_up` | Good quality and above |
| `masterpiece` | General quality booster |
| `high quality` | General quality booster |

### Style Source Tags

| Tag | Style |
|-----|-------|
| `source_pony` | MLP / pony art style |
| `source_furry` | Furry art style |
| `source_anime` | Anime art style |
| `source_cartoon` | Western cartoon style |
| `source_realistic` | Photorealistic human style |

### Prompt Library

All ready-to-use positive/negative prompt combinations are stored in [`prompts.yaml`](prompts.yaml).

| Key | Description |
|-----|-------------|
| `realistic_single_female` | Single female, photorealistic, outdoor |
| `realistic_single_male` | Single male, photorealistic, outdoor |
| `realistic_boy_and_girl` | 1 boy + 1 girl, photorealistic, standing together |
| `cartoon_single_male` | Single male, western cartoon style |
| `general_negative` | Universal negative prompt for any style |

The file also includes recommended **KSampler settings** for single person, multi-person, and img2img workflows.

### Saved Workflows

Complete ComfyUI node graph exports (including prompts and sampler settings) are stored in the [`workflows/`](workflows/) folder. Load them directly in ComfyUI via the **Load** button.

### Tips for Multi-Person Scenes

- Use `(2persons:1.4), (1boy:1.3), (1girl:1.3)` weight emphasis to force two subjects.
- Add `solo, single person, one person` to the **negative** prompt.
- Lower CFG scale to `5-6` and increase steps to `30+` if anatomy is off.
- Use resolution `1216x832` (landscape) for better two-person composition.

---

## Using a Reference Image as a Template

### Option 1: Image-to-Image (img2img)

This takes an input image and regenerates it in the model's style while preserving the general composition.

1. In ComfyUI, right-click the canvas → **Add Node → Image → Load Image**.
2. Upload your template/reference image.
3. Add a **VAE Encode** node and connect the image output to it.
4. Connect the **VAE Encode** output to the **KSampler's `latent_image`** input, replacing the default **Empty Latent Image** node.
5. Adjust the **Denoise** value on the KSampler to control how much the original image is preserved:

| Denoise Value | Effect |
|---------------|--------|
| `0.75` | Heavy restyling, ~25% of original preserved |
| `0.5` | Balanced, ~50% of original preserved |
| `0.3` | Light changes, ~70% of original preserved |

> Place your reference images in the `./input/` folder — it is already mounted to the container at `/opt/ComfyUI/input` and accessible via the Load Image node.

---

### Option 2: ControlNet — Precise Pose and Structure Control

ControlNet extracts structure (pose, edges, depth) from a reference image and applies it precisely to the generated output. Use this when you need to match a specific pose or composition exactly.

#### Setup

1. Download an SDXL-compatible ControlNet model (e.g., `controlnet-openpose-sdxl`) and place it in:
   ```
   models/controlnet/
   ```
2. In ComfyUI, right-click the canvas → **Add Node → Loaders → Load ControlNet Model**.
3. Right-click → **Add Node → Conditioning → Apply ControlNet**.
4. Connect the nodes as follows:
   - Reference image → **Apply ControlNet `image`**
   - ControlNet model → **Apply ControlNet `control_net`**
   - Positive prompt → **Apply ControlNet `conditioning`**
   - Apply ControlNet output → **KSampler `positive`**

#### ControlNet Types

| ControlNet Type | Best For |
|-----------------|----------|
| OpenPose | Matching a specific body pose |
| Canny / Lineart | Preserving edges and outlines |
| Depth | Preserving 3D depth and structure |
| SoftEdge | Softer edge guidance, less rigid |

---

### Which Approach to Use?

| Scenario | Best Option |
|----------|-------------|
| Restyle an existing image | img2img |
| Match a specific pose exactly | ControlNet (OpenPose) |
| Preserve edges / outlines | ControlNet (Canny / Lineart) |
| Preserve depth / structure | ControlNet (Depth) |

---

## Output

Generated images are saved to:

```
./output/
```

This folder is mounted from the container to your host machine, so images persist even after the container is stopped.
