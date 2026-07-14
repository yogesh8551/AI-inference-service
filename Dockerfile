# ==============================================================================
# Stage 1: Build Context & Shared Library Helper
# ==============================================================================
FROM ubuntu:24.04 AS builder

# Copy the build directory from host to helper stage
COPY build /build

# Organize binaries and find any shared libraries (.so files) dynamically
RUN mkdir -p /dist/bin /dist/lib && \
    if [ -f "/build/bin/llama-server" ]; then \
        cp /build/bin/llama-server /dist/bin/; \
    else \
        echo "ERROR: llama-server binary not found in build/bin/!" >&2 && exit 1; \
    fi && \
    # Find all shared libraries (.so files) recursively in the build directory and copy them to /dist/lib/
    find /build -name "*.so*" -exec cp -d {} /dist/lib/ \; 2>/dev/null || true

# ==============================================================================
# Stage 2: Minimal Production Runtime
# ==============================================================================
FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential runtime dependencies (OpenMP for CPU execution, curl for health checks, ca-certificates for secure connections)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a secure, non-root system group and user with predefined system UID/GID (10001)
RUN groupadd -g 10001 llama && \
    useradd -u 10001 -g llama -s /usr/sbin/nologin -M llama

# Copy runtime binaries and shared libraries from helper stage
COPY --from=builder --chown=llama:llama /dist/bin/llama-server /usr/local/bin/llama-server
COPY --from=builder --chown=llama:llama /dist/lib/ /usr/local/lib/

# Update dynamic linker run-time bindings to locate copied shared libraries
RUN ldconfig

# Create /models directory for mounting GGUF model files
RUN mkdir /models && chown llama:llama /models

# Create the entrypoint script inline to avoid requiring entrypoint.sh in the build context
COPY --chown=llama:llama <<'EOF' /usr/local/bin/entrypoint.sh
#!/bin/sh
set -e

# Print initial banner
echo "=== LLAMA-SERVER DOCKER ENTRYPOINT ==="

# Validate model path presence
if [ -z "${MODEL_PATH}" ]; then
    echo "ERROR: MODEL_PATH environment variable is not defined." >&2
    echo "Please set MODEL_PATH to the GGUF model location (e.g. /models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf)." >&2
    exit 1
fi

echo "Target Model Path: ${MODEL_PATH}"

# Check if the model file exists
if [ ! -f "${MODEL_PATH}" ]; then
    echo "ERROR: Model file does not exist at '${MODEL_PATH}'." >&2
    echo "Verify that the model directory is correctly mounted to /models and contains the GGUF file." >&2
    exit 1
fi

echo "Model file successfully verified."
echo "Starting llama-server on ${LLAMA_HOST:-0.0.0.0}:${LLAMA_PORT:-8081}..."

# Execute llama-server as PID 1 to ensure standard Unix signal handling (SIGTERM, SIGINT) works properly.
if [ -n "${LLAMA_EXTRA_ARGS}" ]; then
    echo "Extra arguments provided: ${LLAMA_EXTRA_ARGS}"
    exec llama-server \
        -m "${MODEL_PATH}" \
        --host "${LLAMA_HOST:-0.0.0.0}" \
        --port "${LLAMA_PORT:-8081}" \
        ${LLAMA_EXTRA_ARGS}
else
    exec llama-server \
        -m "${MODEL_PATH}" \
        --host "${LLAMA_HOST:-0.0.0.0}" \
        --port "${LLAMA_PORT:-8081}"
fi
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose default llama-server port
EXPOSE 8081

# Switch to the non-root user
USER llama

# Set default environment variables (can be overridden at runtime)
ENV MODEL_PATH=/models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf \
    LLAMA_HOST=0.0.0.0 \
    LLAMA_PORT=8081 \
    LLAMA_EXTRA_ARGS=""

# Configure entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
