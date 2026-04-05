FROM ghcr.io/ai-dock/comfyui:latest-cuda

# Install ComfyUI-GGUF Python dependency into the ComfyUI venv.
# This makes the install survive container rebuilds without needing
# to exec in and pip install manually after every 'docker compose down'.
RUN /opt/environments/python/comfyui/bin/pip install gguf --no-cache-dir -q
