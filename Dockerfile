# Dockerfile for n8n with ffmpeg, whisper.cpp, and SQLite support
# For Adaptive Game Intelligence Nexus (AGIN)

# ---- Stage 1: Builder ----
# This stage will download sources, compile whisper.cpp for generic CPU,
# attempt static linking of its core libs, and download models.
FROM alpine:3.19 AS builder

# Install build-time dependencies
RUN apk update && \
    apk add --no-cache \
    git \
    build-base \
    cmake \
    bash \
    curl \
    wget && \
    echo "--- Builder stage: Essential build tools installed ---"

WORKDIR /app

# Clone whisper.cpp (latest from main branch), initialize submodules, and compile
RUN echo "Cloning whisper.cpp (main repository)..." && \
    git clone https://github.com/ggerganov/whisper.cpp.git . && \
    echo "Initializing and updating Git submodules (this will fetch ggml and its contents)..." && \
    git submodule init && \
    git submodule update --init --recursive && \
    echo "Verifying crucial submodule file ggml/src/ggml.c:" && \
    ls -lh ggml/src/ggml.c && \
    echo "Attempting to build whisper.cpp with generic CPU flags and attempt static linking..." && \
    # Compile whisper.cpp for generic CPU compatibility (no AVX, etc.)
    # Attempt static linking for core components to reduce runtime dependencies
    make CMAKE_ARGS="\
    -DWHISPER_NO_AVX=ON \
    -DWHISPER_NO_AVX2=ON \
    -DWHISPER_NO_AVX512=ON \
    -DWHISPER_NO_FMA=ON \
    -DWHISPER_NO_F16C=ON \
    -DWHISPER_NO_OPENBLAS=ON \
    -DWHISPER_BUILD_SHARED=OFF \
    -DGGML_BUILD_SHARED=OFF" whisper-cli && \
    echo "--- whisper.cpp CLI compiled ---"

# Download the ggml model using whisper.cpp's script
# We'll use 'small' as it was in your previous setup; can be changed to 'base', 'medium', etc.
RUN echo "Downloading ggml model (small)..." && \
    bash ./models/download-ggml-model.sh small && \
    echo "--- ggml model (small) downloaded ---"


# ---- Stage 2: Final Runtime Image ----
# Start from the official n8n Alpine image you had success with
FROM n8nio/n8n:1.94.0

# Switch to root for installations
USER root

# Install runtime dependencies: ffmpeg for media processing, sqlite for database interactions
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    sqlite && \
    # Clean up apk cache
    rm -rf /var/cache/apk/* && \
    echo "--- Runtime dependencies (ffmpeg, sqlite) installed ---"

# Copy the entire compiled whisper.cpp directory (including models and executables)
# from the builder stage.
COPY --from=builder /app /opt/whisper.cpp

# Set LD_LIBRARY_PATH for any remaining shared libraries from whisper.cpp build,
# though static linking aims to reduce reliance on this for whisper/ggml core.
ENV LD_LIBRARY_PATH="/opt/whisper.cpp/build/src:/opt/whisper.cpp/build/ggml/src:${LD_LIBRARY_PATH}"

# Set PATH for whisper.cpp executables.
# whisper-cli is typically in 'build/bin/' or directly 'build/' after the make command.
# The previous make command `make whisper-cli` places it in the root of the build dir usually.
# Let's ensure both potential paths are covered.
ENV PATH="/opt/whisper.cpp/build/bin:/opt/whisper.cpp/build:/opt/whisper.cpp:${PATH}"

# Ensure executables copied are executable
# (Permissions should be preserved by COPY --from, but this is an explicit safeguard)
# The whisper-cli is now built specifically.
RUN if [ -f /opt/whisper.cpp/build/whisper-cli ]; then chmod +x /opt/whisper.cpp/build/whisper-cli; fi && \
    if [ -f /opt/whisper.cpp/main ]; then chmod +x /opt/whisper.cpp/main; fi && \
    if [ -d /opt/whisper.cpp/build/bin ]; then chmod +x /opt/whisper.cpp/build/bin/*; fi && \
    echo "--- Executable permissions set for whisper.cpp tools ---"

# Switch back to the non-root n8n user
USER node

# Set the working directory for n8n (this is usually handled by the base n8n image,
# but explicitly setting it doesn't hurt if it aligns with N8N_USER_FOLDER practices)
WORKDIR /home/node

# Base n8n image handles the application start (CMD or ENTRYPOINT).
# Expose n8n port (usually handled by base image and Render's service config)
# EXPOSE 5678

RUN echo "--- n8n Docker image build complete. Final user: $(whoami), Working directory: $(pwd) ---"
