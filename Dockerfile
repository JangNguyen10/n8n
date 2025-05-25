# Dockerfile for n8n with ffmpeg, yt-dlp, and whisper.cpp (SMTE vPPLX-OS - Final Syntax Correction)

# ---- Stage 1: Builder ----
# This stage will download sources, compile whisper.cpp, and download models.
FROM alpine:3.19 AS builder

# Install build-time dependencies:
# - git: for cloning
# - build-base: for make/g++
# - cmake: for whisper.cpp's Makefile
# - bash: for scripts
# - curl and wget: for the model download script (whisper.cpp's script prefers wget)
RUN apk update && \
    apk add --no-cache \
    git \
    build-base \
    cmake \
    bash \
    curl \
    wget && \
    echo "--- Installed Wget version: ---" && \
    wget --version && \
    echo "--- Installed Curl version: ---" && \
    curl --version

# Set working directory for whisper.cpp build
WORKDIR /app

# Clone whisper.cpp, initialize submodules, and compile
RUN echo "Cloning whisper.cpp (main repository)..." && \
    git clone https://github.com/ggerganov/whisper.cpp.git . && \
    echo "Initializing and updating Git submodules (this will fetch ggml and its contents)..." && \
    git submodule init && \
    git submodule update --init --recursive && \
    echo "Verifying crucial submodule file ggml/src/ggml.c:" && \
    ls -lh ggml/src/ggml.c && \
    echo "Attempting to build whisper.cpp (default 'make' target)..." && \
    make

# Download the model using whisper.cpp's script
RUN bash ./models/download-ggml-model.sh small


# ---- Stage 2: Final Runtime Image ----
# Start from the official n8n Alpine image
FROM n8nio/n8n:1.94.0

# Switch to root for installations
USER root

# Install runtime dependencies:
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip \
    bash && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# Copy whisper.cpp artifacts from the builder stage.
COPY --from=builder /app /opt/whisper.cpp

# Set the PATH to include the whisper.cpp executables.
ENV PATH="/opt/whisper.cpp:/opt/whisper.cpp/bin:${PATH}"

# Switch back to the non-root n8n user
USER node

# Set the working directory for n8n
WORKDIR /home/node

# Base n8n image handles the application start.
