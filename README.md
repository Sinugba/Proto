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

### CLIP Token Limits and Prompt Length

CLIP (the text encoder used by Stable Diffusion) enforces a **75-token hard limit per chunk**.

#### What happens when your prompt is too long

- ComfyUI automatically splits prompts into 75-token chunks (75, 150, 225 tokens...)
- Tags in **chunk 1 (tokens 1–75)** have the strongest influence on the output
- Tags in **chunk 2+ (tokens 76–150+)** have progressively weaker influence — the model pays less attention to them
- Late-position negatives stop working reliably — e.g. safety exclusion tags that land in chunk 3 lose effectiveness
- Conflicting signals accumulate — the model averages them and outputs a blurry compromise
- Person-count anchors (`1boy`, `1girl`) placed late lose their contract power

> **Rough rule:** 75 tokens ≈ 55–65 words. Commas count as tokens too.
> ComfyUI shows a live token count — hover over any CLIP Text Encode node to see it.

#### Priority order — Positive prompt

Put the highest-impact tags first so they always land in chunk 1:

| Priority | Tags |
|----------|------|
| 1 | Quality prefix (`score_9, score_8_up, score_7_up`) |
| 2 | Subject count (`1boy, 1girl, adult`) |
| 3 | Key action / scene |
| 4 | Face and body quality tags |
| 5 (cut first) | Background and lighting |

#### Priority order — Negative prompt

| Priority | Tags |
|----------|------|
| 1 | Safety exclusions (`child, minor, loli, elderly...`) |
| 2 | Anatomy defects (`bad anatomy, deformed hands...`) |
| 3 | Quality (`score_4, score_5, score_6`) |
| 4 (cut first) | Background artifacts |

#### What to do if you're over the limit

- Remove tips from the CLIP Text Encode node — they are for humans reading `prompts.yaml`, not for the model
- Cut background/lighting tags from the positive (least impactful)
- Cut background artifact tags from the negative
- Merge near-duplicate tags: `deformed face, bad face, warped face` → keep one or two, drop the rest

---

## ComfyUI Node Wiring Reference

### Default Text-to-Image Workflow

The default workflow node connections:

```
[Load Checkpoint] ──MODEL──► [KSampler] model
[Load Checkpoint] ──CLIP───► [CLIP Text Encode +] ──CONDITIONING──► [KSampler] positive
[Load Checkpoint] ──CLIP───► [CLIP Text Encode -] ──CONDITIONING──► [KSampler] negative
[Load Checkpoint] ──VAE────► [VAE Decode] vae

[Empty Latent Image] ──LATENT──► [KSampler] latent_image

[KSampler] ──LATENT──► [VAE Decode] samples
[VAE Decode] ──IMAGE──► [Save Image]
```

**Load Checkpoint outputs (3 dots on the right side):**

| Output | Connects to |
|--------|-------------|
| `MODEL` (top) | KSampler `model` |
| `CLIP` (middle) | Both CLIP Text Encode nodes `clip` |
| `VAE` (bottom) | VAE Decode `vae` and VAE Encode `vae` |

---

### Adding Nodes

- **Right-click** on empty canvas → browse the menu to find nodes by category.
- **Double-click** on empty canvas → opens a search box, type the node name.

---

## Using a Reference Image as a Template

### Option 1: Image-to-Image (img2img)

This takes an input image and regenerates it in the model's style while preserving the general composition.

#### Adding the VAE Encode node

1. Double-click on empty canvas → type `VAE Encode` → click to add it.
2. Right-click canvas → **Add Node → Image → Load Image** to add the image loader.

#### Full img2img node wiring

```
[Load Checkpoint] ──MODEL──► [KSampler] model
[Load Checkpoint] ──CLIP───► [CLIP Text Encode +] ──CONDITIONING──► [KSampler] positive
[Load Checkpoint] ──CLIP───► [CLIP Text Encode -] ──CONDITIONING──► [KSampler] negative
[Load Checkpoint] ──VAE────► [VAE Encode] vae
[Load Checkpoint] ──VAE────► [VAE Decode] vae

[Load Image] ──IMAGE──► [VAE Encode] pixels

[VAE Encode] ──LATENT──► [KSampler] latent_image

[KSampler] ──LATENT──► [VAE Decode] samples
[VAE Decode] ──IMAGE──► [Save Image]
```

> **Important:** Disconnect or delete the **Empty Latent Image** node and replace it with the **VAE Encode** output connected to the KSampler `latent_image` input.

#### Denoise settings

Adjust the **Denoise** value on the KSampler to control how much of the original image is preserved:

| Denoise | Prompt Influence | Image Influence | Use When |
|---------|-----------------|-----------------|----------|
| `0.9` | Very strong | Weak | Heavy restyle |
| `0.75` | Strong | Moderate | Default starting point |
| `0.5` | Balanced | Balanced | Balanced restyle |
| `0.3` | Weak | Strong | Light touch / minor changes |

#### Prompts in img2img

Prompts work identically to text-to-image — enter them in the **CLIP Text Encode** nodes. Higher denoise = prompt has stronger influence over the final image.

> Place your reference images in the `./input/` folder — it is mounted to `/opt/ComfyUI/input` inside the container and accessible via the Load Image node.

---

### Option 2: ControlNet — Precise Pose and Structure Control

ControlNet extracts structure (pose, edges, depth) from a reference image and applies it precisely to the generated output. Use this when you need to match a specific pose or composition exactly.

#### Setup

1. Download an SDXL-compatible ControlNet model (e.g., `controlnet-openpose-sdxl`) and place it in:
   ```
   models/controlnet/
   ```
2. Double-click canvas → search `Load ControlNet Model` → add it.
3. Double-click canvas → search `Apply ControlNet` → add it.

#### ControlNet node wiring

```
[Load Checkpoint] ──MODEL──► [KSampler] model
[Load Checkpoint] ──CLIP───► [CLIP Text Encode +] ──CONDITIONING──► [Apply ControlNet] conditioning
[Load Checkpoint] ──CLIP───► [CLIP Text Encode -] ──CONDITIONING──► [KSampler] negative
[Load Checkpoint] ──VAE────► [VAE Decode] vae

[Load ControlNet Model] ──CONTROL_NET──► [Apply ControlNet] control_net
[Load Image] ──IMAGE──► [Apply ControlNet] image

[Apply ControlNet] ──CONDITIONING──► [KSampler] positive

[Empty Latent Image] ──LATENT──► [KSampler] latent_image
[KSampler] ──LATENT──► [VAE Decode] samples
[VAE Decode] ──IMAGE──► [Save Image]
```

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

## Inpaint Mask — Body / Clothing Restyle Step-by-Step

Use this when you want to change the body or clothing of a subject while keeping the face and background completely intact.

### Required nodes

| Node | Purpose |
|------|---------|
| **Load Image** | Source image to restyle |
| **Load Image** (second instance, mask output) | Painted mask |
| **VAE Encode (for Inpainting)** | Encodes image + mask together |
| **KSampler** | Runs diffusion only on masked region |
| **VAE Decode** | Decodes latent back to image |
| **Save Image** | Saves result |

### Step 1 — Paint the mask in ComfyUI

1. Add a **Load Image** node and load your source image.
2. Right-click the **Load Image** node → **Open in MaskEditor**.
3. In the mask editor:
   - Paint **white** over the body and clothing area you want to change.
   - Leave the **face, hair, neck, and background black** — black regions are not touched.
   - Use the brush size slider for precision around the face/shoulder boundary.
4. Click **Save** — the mask is now stored on the Load Image node's mask output.

### Step 2 — Wire the inpaint nodes

```
[Load Checkpoint] ──MODEL──────────────────────────────► [KSampler] model
[Load Checkpoint] ──CLIP────► [CLIP Text Encode +] ──► [KSampler] positive
[Load Checkpoint] ──CLIP────► [CLIP Text Encode -] ──► [KSampler] negative
[Load Checkpoint] ──VAE─────► [VAE Encode (Inpaint)] vae
[Load Checkpoint] ──VAE─────► [VAE Decode] vae

[Load Image] ──IMAGE──► [VAE Encode (Inpaint)] pixels
[Load Image] ──MASK───► [VAE Encode (Inpaint)] mask

[VAE Encode (Inpaint)] ──LATENT──► [KSampler] latent_image

[KSampler] ──LATENT──► [VAE Decode] samples
[VAE Decode] ──IMAGE──► [Save Image]
```

> **Important:** Use **VAE Encode (for Inpainting)** — not the regular VAE Encode. The inpainting version takes a `mask` input alongside `pixels`.

### Step 3 — Set KSampler values

| Setting | Body restyle | Clothing only |
|---------|-------------|---------------|
| `denoise` | **0.8** | **0.55** |
| `steps` | 25 | 20 |
| `cfg_scale` | 6 | 7 |
| `sampler` | dpmpp_2m | dpmpp_2m |
| `scheduler` | karras | karras |

- **Denoise too low** (< 0.7): nothing changes inside the mask
- **Denoise too high** (> 0.9): face/background bleeds into the masked region

### Step 4 — Write your prompt

In the **positive CLIP Text Encode** node, describe what the masked region should look like:

```
score_9, score_8_up, score_7_up, source_realistic, masterpiece, high quality,
fit body, casual outfit, standing, natural lighting
```

Replace `fit body, casual outfit` with your target — e.g.:
- `muscular build, black hoodie and jeans`
- `slender figure, red sundress, sleeveless`
- `athletic wear, sports bra, leggings`

Use the prompt key `pony_img2img_restyle_body` or `pony_img2img_restyle_clothing` from [`prompts.yaml`](prompts.yaml) as your starting point.

### How the mask works

| Mask color | Effect |
|------------|--------|
| **White** | Model regenerates this region using your prompt |
| **Black** | Copied directly from the source image — unchanged |

The face is protected by painting it black, not by any prompt tag. Do **not** add `same face` or `same person` to your positive prompt — those tags suppress change in the entire image, including the masked region.

---

## Output

Generated images are saved to:

```
./output/
```

This folder is mounted from the container to your host machine, so images persist even after the container is stopped.
