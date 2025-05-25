# Dockerfile for n8n with ffmpeg, yt-dlp, and whisper.cpp (SMTE vPPLX-OS - Prime Directive Version)

# ---- Stage 1: Builder ----
# This stage will download sources, compile whisper.cpp for generic CPU,
# attempt static linking of its core libs, and download models.
FROM alpine:3.19 AS builder

# Install build-time dependencies
# git, build-base, cmake for whisper.cpp compilation
# bash for scripts, curl & wget for model download
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

WORKDIR /app

# Clone whisper.cpp, initialize submodules, and compile
RUN echo "Cloning whisper.cpp (main repository)..." && \
    git clone https://github.com/ggerganov/whisper.cpp.git . && \
    echo "Initializing and updating Git submodules (this will fetch ggml and its contents)..." && \
    git submodule init && \
    git submodule update --init --recursive && \
    echo "Verifying crucial submodule file ggml/src/ggml.c:" && \
    ls -lh ggml/src/ggml.c && \
    echo "Attempting to build whisper.cpp with generic CPU flags and attempt static linking..." && \
    make CMAKE_ARGS="\
    -DWHISPER_NO_AVX=ON \
    -DWHISPER_NO_AVX2=ON \
    -DWHISPER_NO_AVX512=ON \
    -DWHISPER_NO_FMA=ON \
    -DWHISPER_NO_F16C=ON \
    -DWHISPER_NO_OPENBLAS=ON \
    -DWHISPER_BUILD_SHARED=OFF \
    -DGGML_BUILD_SHARED=OFF"

# Download the model using whisper.cpp's script
RUN bash ./models/download-ggml-model.sh small


# ---- Stage 2: Final Runtime Image ----
# Start from the official n8n Alpine image
FROM n8nio/n8n:1.94.0

# Switch to root for installations
USER root

# Install runtime dependencies
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip \
    bash && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# Copy the entire compiled whisper.cpp directory (including models and executables)
# from the builder stage.
COPY --from=builder /app /opt/whisper.cpp

# Set LD_LIBRARY_PATH for any remaining shared libraries from whisper.cpp build,
# though static linking aims to reduce reliance on this for whisper/ggml core.
# These paths are where CMake might place .so files for sub-projects if not fully static.
ENV LD_LIBRARY_PATH="/opt/whisper.cpp/build/src:/opt/whisper.cpp/build/ggml/src:${LD_LIBRARY_PATH}"

# Set PATH for whisper.cpp executables.
# CMake typically places executables in 'build/bin/' relative to the project root.
# The root Makefile might also place 'main' in the project root.
ENV PATH="/opt/whisper.cpp/build/bin:/opt/whisper.cpp:${PATH}"

# Ensure executables copied are executable by all
# (Permissions should be preserved by COPY --from, but this is an explicit safeguard)
RUN chmod +x /opt/whisper.cpp/build/bin/* /opt/whisper.cpp/main || true

# Switch back to the non-root n8n user
USER node

# Set the working directory for n8n
WORKDIR /home/node

# Base n8n image handles the application start.
