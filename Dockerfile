# Dockerfile for n8n with ffmpeg, yt-dlp, and whisper.cpp (multilingual model)

# STEP 1: CHOOSE A BASE N8N IMAGE (Using 1.94.0, assumed Alpine)
FROM n8nio/n8n:1.94.0

# STEP 2: SWITCH TO ROOT USER
USER root

# STEP 3: INSTALL SYSTEM DEPENDENCIES for Alpine (ffmpeg, git, build-base, python3, py3-pip, yt-dlp)
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    git \
    build-base \
    python3 \
    py3-pip && \
    pip3 install --no-cache-dir --break-system-packages yt-dlp && \
    rm -rf /var/cache/apk/*

# STEP 4: CLONE AND COMPILE WHISPER.CPP
# Executable will be at /opt/whisper.cpp/main
RUN git clone https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp && \
    cd /opt/whisper.cpp && \
    make main

# STEP 5: DOWNLOAD WHISPER.CPP "SMALL" MULTILINGUAL MODEL
# Selected for balance on Render Starter Plan (512MB RAM, 0.5 CPU).
# Model will be at /opt/whisper.cpp/models/ggml-small.bin
RUN cd /opt/whisper.cpp && \
    bash ./models/download-ggml-model.sh small

# STEP 6: ADD WHISPER.CPP TO SYSTEM PATH for easier execution
ENV PATH="/opt/whisper.cpp:${PATH}"

# STEP 7: SWITCH BACK TO NON-ROOT N8N USER (typically 'node')
USER node

# STEP 8: (IMPLICIT) N8N STARTUP VIA BASE IMAGE CMD/ENTRYPOINT
# Base n8n image handles the application start.
