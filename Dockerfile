# Dockerfile for n8n with ffmpeg, yt-dlp, and whisper.cpp (SMTE vPPLX-OS - Syntax Fix)

# STEP 1: CHOOSE A BASE N8N IMAGE (Using 1.94.0, Alpine-based)
FROM n8nio/n8n:1.94.0

# STEP 2: SWITCH TO ROOT USER
USER root

# STEP 3: INSTALL SYSTEM DEPENDENCIES for Alpine
# Includes: ffmpeg, git, build-base, cmake, python3, py3-pip, and yt-dlp
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    git \
    build-base \
    cmake \
    python3 \
    py3-pip && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# STEP 4: CLONE AND COMPILE WHISPER.CPP
# Executable 'main' is expected in /opt/whisper.cpp after 'make'
RUN rm -rf /opt/whisper.cpp && \
    echo "Cloning whisper.cpp (main repository)..." && \
    git clone https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp && \
    cd /opt/whisper.cpp && \
    echo "Initializing and updating Git submodules (this will fetch ggml and its contents)..." && \
    git submodule init && \
    git submodule update --init --recursive && \
    echo "Verifying crucial submodule file ggml/src/ggml.c:" && \
    ls -lh ggml/src/ggml.c && \
    echo "Attempting to build whisper.cpp (default 'make' target)..." && \
    make

# STEP 5: DOWNLOAD WHISPER.CPP "SMALL" MULTILINGUAL MODEL
# Model will be at /opt/whisper.cpp/models/ggml-small.bin
RUN cd /opt/whisper.cpp && \
    bash ./models/download-ggml-model.sh small

# STEP 6: ADD WHISPER.CPP TO SYSTEM PATH for easier execution
# 'main' executable is created by 'make' in the root of /opt/whisper.cpp
ENV PATH="/opt/whisper.cpp:${PATH}"

# STEP 7: SWITCH BACK TO NON-ROOT N8N USER (typically 'node')
USER node

# STEP 8: (IMPLICIT) N8N STARTUP VIA BASE IMAGE CMD/ENTRYPOINT
# Base n8n image handles the application start.
