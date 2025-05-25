# Dockerfile for n8n with ffmpeg, yt-dlp, and whisper.cpp (SMTE vPPLX-OS - Definitive Multi-Stage)

# ---- Stage 1: Builder ----
# This stage will download sources, compile whisper.cpp, and download models.
FROM alpine:3.19 AS builder

ARG WHISPER_CPP_REPO=https://github.com/ggerganov/whisper.cpp.git

# Install build-time dependencies.
# - git: for cloning
# - build-base: for make, g++, etc.
# - cmake: required by whisper.cpp's Makefile
# - bash: for running scripts
# - curl: robust for downloads (whisper.cpp script can use it)
# - gnu-wget: full wget for compatibility if download script insists on using wget with GNU options
RUN apk update && \
    apk add --no-cache \
    git \
    build-base \
    cmake \
    bash \
    curl \
    gnu-wget && \
    echo "--- Installed Wget version: ---" && \
    wget --version && \
    echo "--- Installed Curl version: ---" && \
    curl --version

WORKDIR /app # Set WORKDIR for subsequent commands

# Clone whisper.cpp, initialize submodules, and compile
RUN echo "Cloning whisper.cpp from ${WHISPER_CPP_REPO} into /app ..." && \
    git clone ${WHISPER_CPP_REPO} . && \
    echo "Initializing and updating Git submodules (this will fetch ggml and its contents)..." && \
    git submodule init && \
    git submodule update --init --recursive && \
    echo "Verifying crucial submodule file ggml/src/ggml.c:" && \
    ls -lh ggml/src/ggml.c && \
    echo "Attempting to build whisper.cpp (default 'make' target)..." && \
    make

# Download the model using whisper.cpp's script.
# This runs in WORKDIR /app where whisper.cpp was cloned and built.
# The script should now work with gnu-wget or fall back to curl.
RUN bash ./models/download-ggml-model.sh small


# ---- Stage 2: Final Runtime Image ----
FROM n8nio/n8n:1.94.0

# Switch to root for installations
USER root

# Install runtime dependencies:
# - ffmpeg: for media processing
# - python3, py3-pip: for yt-dlp
# - bash: as scripts might expect it
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip \
    bash && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# Create the target directory for whisper.cpp artifacts and set it as WORKDIR for COPY.
WORKDIR /opt/whisper.cpp

# Copy compiled whisper.cpp artifacts (executables, libraries) and the downloaded models
# from the builder stage's /app directory.
COPY --from=builder /app /opt/whisper.cpp

# Set the PATH to include the whisper.cpp directory where 'main' and other executables are.
# The `make` process for whisper.cpp places 'main' in the root of its source tree
