# Dockerfile for n8n with ffmpeg, whisper.cpp, and SQLite support
# For Adaptive Game Intelligence Nexus (AGIN)
# Base n8n version: 1.94.0
# Includes whisper.cpp compiled from latest source with generic CPU flags
# Includes ffmpeg and sqlite

# ---- Stage 1: Builder ----
# This stage will download sources, compile whisper.cpp for generic CPU,
# attempt static linking of its core libs, and download models.
FROM alpine:3.19 AS builder

# Install build-time dependencies for whisper.cpp and fetching assets
RUN apk update && \
    apk add --no-cache \
    git \
    build-base \
    cmake \
    bash \
    curl \
    wget && \
    echo "--- Builder stage: Essential build tools installed (git, cmake, etc.) ---"

WORKDIR /app

# Clone whisper.cpp (latest from main branch), initialize submodules
RUN echo "Cloning whisper.cpp (main repository from GitHub)..." && \
    git clone https://github.com/ggerganov/whisper.cpp.git . && \
    echo "Initializing and updating Git submodules (fetches ggml)..." && \
    git submodule init && \
    git submodule update --init --recursive && \
    echo "Verifying crucial submodule file ggml/src/ggml.c:" && \
    ls -lh ggml/src/ggml.c

# Compile whisper.cpp
# Using CMAKE_ARGS for generic CPU compatibility (no AVX, etc.)
# Attempting static linking for core components to reduce runtime dependencies.
# The 'make' command will build default targets, which includes whisper-cli and other tools.
RUN echo "Attempting to build whisper.cpp default targets (including whisper-cli)..." && \
    make CMAKE_ARGS="\
    -DWHISPER_NO_AVX=ON \
    -DWHISPER_NO_AVX2=ON \
    -DWHISPER_NO_AVX512=ON \
    -DWHISPER_NO_FMA=ON \
    -DWHISPER_NO_F16C=ON \
    -DWHISPER_NO_OPENBLAS=ON \
    -DWHISPER_BUILD_SHARED=OFF \
    -DGGML_BUILD_SHARED=OFF" && \
    echo "--- whisper.cpp tools compiled ---"

# Download the ggml model using whisper.cpp's script
# Using 'small' model as per previous setup; can be changed to 'base', 'medium', etc. if needed.
RUN echo "Downloading ggml model (small)..." && \
    bash ./models/download-ggml-model.sh small && \
    echo "--- ggml model (small) downloaded to ./models/ggml-small.bin ---"


# ---- Stage 2: Final Runtime Image ----
# Start from the official n8n Alpine image you had success with
FROM n8nio/n8n:1.94.0

# Switch to root user for installations
USER root

# Install runtime dependencies:
# - ffmpeg: for media processing (Node 5 in our AGIN plan)
# - sqlite: for SQLite database interactions (Node 7 & AGIN's persistent store)
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    sqlite && \
    # Clean up apk cache to reduce image size
    rm -rf /var/cache/apk/* && \
    echo "--- Runtime dependencies (ffmpeg, sqlite) installed ---"

# Copy the entire compiled whisper.cpp directory (including models and executables)
# from the builder stage to /opt/whisper.cpp in the final image.
COPY --from=builder /app /opt/whisper.cpp

# Set LD_LIBRARY_PATH for any remaining shared libraries from whisper.cpp build.
# Static linking aims to reduce reliance on this, but good as a fallback.
ENV LD_LIBRARY_PATH="/opt/whisper.cpp/build/src:/opt/whisper.cpp/build/ggml/src:${LD_LIBRARY_PATH}"

# Set PATH for whisper.cpp executables.
# whisper-cli and other binaries are typically in 'build/bin/' or 'build/' after compilation.
# Including /opt/whisper.cpp itself in case some scripts or main executable are there.
ENV PATH="/opt/whisper.cpp/build/bin:/opt/whisper.cpp/build:/opt/whisper.cpp:${PATH}"

# Ensure key executables copied from the builder stage are executable by the runtime user.
# (Permissions should ideally be preserved by COPY --from=builder, but this is an explicit safeguard)
# Specifically targeting common locations for whisper-cli or main executables.
RUN \
    if [ -f /opt/whisper.cpp/build/whisper-cli ]; then chmod +x /opt/whisper.cpp/build/whisper-cli; echo "Set +x on /opt/whisper.cpp/build/whisper-cli"; fi && \
    if [ -f /opt/whisper.cpp/build/bin/whisper-cli ]; then chmod +x /opt/whisper.cpp/build/bin/whisper-cli; echo "Set +x on /opt/whisper.cpp/build/bin/whisper-cli"; fi && \
    if [ -f /opt/whisper.cpp/main ]; then chmod +x /opt/whisper.cpp/main; echo "Set +x on /opt/whisper.cpp/main"; fi && \
    # General execute permission for anything in build/bin if it exists
    if [ -d /opt/whisper.cpp/build/bin ]; then chmod +x /opt/whisper.cpp/build/bin/*; fi && \
    echo "--- Executable permissions checked/set for whisper.cpp tools ---"

# Switch back to the non-root n8n user (typically 'node')
USER node

# Set the working directory for n8n.
# The base n8n image usually sets this to /home/node.
# N8N_USER_FOLDER is an environment variable that dictates where n8n stores its own data (like SQLite DB, config).
WORKDIR /home/node

# The base n8n image's CMD or ENTRYPOINT will start n8n.
# Default n8n port is 5678 (already exposed by base image and managed by Render).

RUN echo "--- n8n Docker image for AGIN build complete. Current user: $(whoami), Working directory: $(pwd) ---"
