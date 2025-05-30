# Dockerfile for n8n with ffmpeg, whisper.cpp, and SQLite support
# For Adaptive Game Intelligence Nexus (AGIN)
# Base n8n version: 1.94.0
# Includes whisper.cpp compiled from a specific stable release tag with generic CPU flags
# Includes ffmpeg, sqlite CLI, wget, and build tools for better-sqlite3
# Includes better-sqlite3 for Node.js custom functions
# Includes NODE_PATH environment variable for global module resolution
# Includes HEALTHCHECK for n8n application monitoring

# ---- Stage 1: Builder ----
# This stage will download sources, compile whisper.cpp for generic CPU,
# attempt static linking of its core libs, and download models.
FROM alpine:3.19 AS builder

# Define whisper.cpp version as an argument to easily update it
# Please check for the latest stable release tag on the whisper.cpp GitHub repository.
# As of last check, v1.5.5 was a recent stable version.
ARG WHISPER_CPP_VERSION=v1.5.5

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

# Clone specific version of whisper.cpp, initialize submodules
RUN echo "Cloning whisper.cpp version ${WHISPER_CPP_VERSION} from GitHub..." && \
    git clone --depth 1 --branch ${WHISPER_CPP_VERSION} https://github.com/ggerganov/whisper.cpp.git . && \
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

# Install runtime dependencies AND ESSENTIAL BUILD DEPENDENCIES for better-sqlite3
# - ffmpeg: for media processing
# - sqlite: for SQLite database interactions (CLI tool)
# - python3, make, g++: Required by node-gyp to compile better-sqlite3 from source
# - wget: Added for the HEALTHCHECK command
RUN apk update && \
    apk add --no-cache \
    ffmpeg \
    sqlite \
    python3 \
    make \
    g++ \
    wget && \
    # Clean up apk cache to reduce image size
    rm -rf /var/cache/apk/* && \
    echo "--- Runtime & Build dependencies (ffmpeg, sqlite CLI, python3, make, g++, wget) installed ---"

# Install better-sqlite3 globally using npm
# This makes it accessible to Node.js scripts executed by n8n's Function node.
# The --build-from-source flag is crucial for native addons.
RUN echo "Attempting to install better-sqlite3 globally using npm..." && \
    npm install -g better-sqlite3 --build-from-source && \
    echo "--- better-sqlite3 successfully installed globally ---"

# Copy the entire compiled whisper.cpp directory (including models and executables)
# from the builder stage to /opt/whisper.cpp in the final image.
COPY --from=builder /app /opt/whisper.cpp

# Set LD_LIBRARY_PATH for whisper.cpp (if its components rely on shared libs within its build dir)
# This is generally good practice if whisper.cpp was compiled with shared libraries,
# though our CMAKE_ARGS aim for static linking of ggml/whisper.
ENV LD_LIBRARY_PATH="/opt/whisper.cpp/build/src:/opt/whisper.cpp/build/ggml/src:${LD_LIBRARY_PATH}"

# Set PATH for whisper.cpp executables (main executable and tools in build/bin)
# Refined PATH to be more precise
ENV PATH="/opt/whisper.cpp:/opt/whisper.cpp/build/bin:${PATH}"

# Set NODE_PATH to include global npm modules directory
# This helps Node.js 'require()' find globally installed packages like better-sqlite3
ENV NODE_PATH="/usr/local/lib/node_modules:${NODE_PATH}"

# Ensure key executables copied from the builder stage are executable.
RUN \
    if [ -f /opt/whisper.cpp/main ]; then chmod +x /opt/whisper.cpp/main; echo "Set +x on /opt/whisper.cpp/main"; fi && \
    if [ -d /opt/whisper.cpp/build/bin ]; then chmod +x /opt/whisper.cpp/build/bin/*; echo "Set +x on executables in /opt/whisper.cpp/build/bin/"; fi && \
    # Redundant check for whisper-cli if covered by build/bin/*, kept for explicitness from original
    if [ -f /opt/whisper.cpp/build/whisper-cli ]; then chmod +x /opt/whisper.cpp/build/whisper-cli; echo "Set +x on /opt/whisper.cpp/build/whisper-cli (if exists standalone)"; fi && \
    if [ -f /opt/whisper.cpp/build/bin/whisper-cli ]; then chmod +x /opt/whisper.cpp/build/bin/whisper-cli; echo "Set +x on /opt/whisper.cpp/build/bin/whisper-cli (if exists here)"; fi && \
    echo "--- Executable permissions checked/set for whisper.cpp tools ---"

# Add HEALTHCHECK for n8n application monitoring
# n8n listens on port 5678 by default. The base path '/' usually returns 200 OK if n8n is running.
# --start-period gives n8n time to initialize before checks count against retries.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget --no-verbose --spider --quiet http://localhost:5678/ || exit 1

# Switch back to the non-root n8n user (typically 'node')
USER node

# Set the working directory for n8n.
WORKDIR /home/node

RUN echo "--- n8n Docker image for AGIN build complete. Current user: $(whoami), Working directory: $(pwd) ---"
