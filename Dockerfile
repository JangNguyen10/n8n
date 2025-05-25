FROM n8nio/n8n:1.94.0

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    build-essential \
    python3 \
    python3-pip && \
    pip3 install --no-cache-dir yt-dlp && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/ggerganov/whisper.cpp.git /opt/whisper.cpp && \
    cd /opt/whisper.cpp && \
    make main

RUN cd /opt/whisper.cpp && \
    bash ./models/download-ggml-model.sh small

ENV PATH="/opt/whisper.cpp:${PATH}"

USER node
