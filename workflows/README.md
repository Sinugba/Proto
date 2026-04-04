# workflows/

Place ComfyUI workflow `.json` files in this folder to save and restore complete generation setups.

## How to save a workflow from ComfyUI

1. In ComfyUI, set up your nodes, prompts, and sampler settings.
2. Click **Save** (top menu) → saves a `.json` file.
3. Rename it descriptively and place it here, e.g.:
   - `realistic_single_female.json`
   - `realistic_two_people.json`
   - `cartoon_single_male.json`

## How to load a workflow

1. In ComfyUI, click **Load** (top menu).
2. Select the `.json` file from this folder.
3. All nodes, prompts, and settings will be restored exactly.

## Naming Convention

```
<style>_<subject>_<variant>.json
```

Examples:
- `realistic_1girl_outdoor.json`
- `realistic_2persons_casual.json`
- `cartoon_1boy_dynamic.json`
- `img2img_restyle.json`
