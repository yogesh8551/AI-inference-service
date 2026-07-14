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

# Copy and prepare entrypoint script
COPY --chown=llama:llama entrypoint.sh /usr/local/bin/entrypoint.sh
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
