# Dockerfile (Diagnostic Version for STEP 4)

# STEP 1: CHOOSE A BASE N8N IMAGE (Using 1.94.0, Alpine-based)
FROM n8nio/n8n:1.94.0

# STEP 2: SWITCH TO ROOT USER
USER root

# STEP 3: INSTALL SYSTEM DEPENDENCIES for Alpine
# Includes: ffmpeg, git, build-base (for make/g++), python3, py3-pip, and yt-dlp
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    git \
    build-base \
    python3 \
    py3-pip && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# STEP 4: CLONE AND COMPILE WHISPER.CPP (Enhanced Diagnostics for Submodule)
RUN rm -rf /opt/whisper.cpp && \
    echo "Current Git version:" && \
    git --version && \
    echo "Cloning whisper.cpp recursively..." && \
    git clone --recursive https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp && \
    cd /opt/whisper.cpp && \
    echo "--- Git Submodule Status (after clone --recursive) ---" && \
    git submodule status --recursive && \
    echo "--- Listing contents of /opt/whisper.cpp (root of whisper.cpp) ---" && \
    ls -la && \
    echo "--- Listing contents of /opt/whisper.cpp/ggml directory (if it exists) ---" && \
    ls -la ggml && \
    echo "--- Checking for crucial submodule file ggml/ggml.c specifically ---" && \
    ls -lh ggml/ggml.c && \
    echo "--- Attempting to build whisper.cpp main target (EXPECTED TO FAIL if ggml.c is missing) ---" && \
    make main

# STEP 5: DOWNLOAD WHISPER.CPP "SMALL" MULTILINGUAL MODEL
# Model will be at /opt/whisper.cpp/models/ggml-small.bin
RUN cd /opt/whisper.cpp && \
    bash ./models/download-ggml-model.sh small

# STEP 6: ADD WHISPER.CPP TO SYSTEM PATH for easier execution
ENV PATH="/opt/whisper.cpp:${PATH}"

# STEP 7: SWITCH BACK TO NON-ROOT N8N USER (typically 'node')
USER node

# STEP 8: (IMPLICIT) N8N STARTUP VIA BASE IMAGE CMD/ENTRYPOINT
# Base n8n image handles the application start.
