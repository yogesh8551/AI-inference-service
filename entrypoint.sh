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
