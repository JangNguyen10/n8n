# Dockerfile for n8n with ffmpeg, yt-dlp, and whisper.cpp (SMTE vPPLX-OS - Multi-Stage, Corrected wget)

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
    wget && \ # Corrected from gnu-wget to wget
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
# This script uses wget (now the full GNU version) or curl.
RUN bash ./models/download-ggml-model.sh small


# ---- Stage 2: Final Runtime Image ----
# Start from the official n8n Alpine image
FROM n8nio/n8n:1.94.0

# Switch to root for installations
USER root

# Install runtime dependencies:
# - ffmpeg: for media processing
# - python3, py3-pip: for yt-dlp
# - bash: as the model download script was run with it (though not strictly needed in final if script isn't re-run)
# We include bash here just in case any copied script from whisper.cpp might still be invoked or for general utility.
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip \
    bash && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# Create the target directory and copy whisper.cpp artifacts from the builder stage.
# This includes compiled executables (like 'main' in /app/ or 'bin/main' in /app/build/) and models.
# We copy the entire /app structure from builder which contains the compiled whisper.cpp and models.
COPY --from=builder /app /opt/whisper.cpp

# Set the PATH to include the whisper.cpp directory.
# 'make' for whisper.cpp (via CMake) usually places executables in a 'bin' subdirectory of its build dir,
# or sometimes directly in the root (like './main').
# Based on previous successful compile log, executables were in a 'bin' dir (e.g., /app/bin/main).
# After COPY, this becomes /opt/whisper.cpp/bin/main.
# The main executable is often also placed at /opt/whisper.cpp/main by the root Makefile.
# Including both /opt/whisper.cpp and /opt/whisper
