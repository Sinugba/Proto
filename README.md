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

---

### Prompt Examples

#### `source_realistic` — Photorealistic Human Figure

**Positive:**
```
score_9, score_8_up, score_7_up, source_realistic, 1girl, solo, detailed face, beautiful eyes, long brown hair, casual outfit, standing, outdoor background, natural lighting, masterpiece, high quality, detailed skin, sharp focus, looking at viewer
```

**Negative:**
```
score_4, score_5, score_6, bad anatomy, extra limbs, deformed hands, bad hands, missing fingers, fused fingers, mutated, low quality, blurry, watermark, text, ugly, disfigured
```

**Tips:**
- Use `1girl` / `1boy` / `1person` to define subject count and gender.
- Add `solo` to keep focus on a single subject.
- Describe hair (`long brown hair`), clothing (`casual outfit`), and setting (`outdoor background`) for more control.
- Always include `deformed hands, bad hands, missing fingers` in the negative prompt — hand anatomy is the most common failure point.

---

#### `source_cartoon` — Western Cartoon Style Human Figure

**Positive:**
```
score_9, score_8_up, score_7_up, source_cartoon, 1boy, solo, expressive face, stylized proportions, colorful outfit, dynamic pose, bright background, masterpiece, high quality, clean lineart, vibrant colors
```

**Negative:**
```
score_4, score_5, score_6, bad anatomy, extra limbs, deformed, low quality, blurry, realistic, photo, watermark, text, grainy
```

**Tips:**
- Add `clean lineart` and `vibrant colors` to enhance the cartoon aesthetic.
- Use `dynamic pose` or `action pose` for more energetic compositions.
- Add `realistic` and `photo` to the negative prompt to prevent the model from drifting toward photorealism.
- `expressive face` works well for cartoon styles to get exaggerated, readable emotions.

---

### General Negative Prompt (works for all styles)

```
score_4, score_5, score_6, bad anatomy, extra limbs, deformed hands, bad hands, missing fingers, fused fingers, low quality, blurry, watermark, text, ugly, disfigured, mutated
```

---

## Output

Generated images are saved to:

```
./output/
```

This folder is mounted from the container to your host machine, so images persist even after the container is stopped.
