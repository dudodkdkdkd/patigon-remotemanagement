#!/bin/bash
# ==============================================================================
# Claude Code & Codex Local Development Script (devstart)
# ==============================================================================
# Runs remote control instances interactively in the foreground.
# Prioritizes local project environment and resolves CLI paths using system PATH.

set -e

# Root Check
if [ "$EUID" -ne 0 ]; then
    echo "Fehler: Bitte mit sudo ausführen." >&2
    exit 1
fi

# Helper to resolve absolute directory path
resolve_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        (cd "$dir" && pwd)
        return 0
    fi
    return 1
}

# Helper to find a secret directory (candidates)
find_secret_dir() {
    local candidates=()
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [ -n "${SECRET_DIR:-}" ]; then
        candidates+=("$SECRET_DIR")
    fi
    candidates+=(
        "/secret"
        "${script_dir}/../SECRET"
        "${script_dir}/../secret"
        "${script_dir}/../../SECRET"
        "${script_dir}/../../secret"
    )
    for candidate in "${candidates[@]}"; do
        if resolved="$(resolve_dir "$candidate" 2>/dev/null)"; then
            echo "$resolved"
            return 0
        fi
    done
    return 1
}

# Determine project root and local .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f ".env" ]; then
    ENV_FILE="$(pwd)/.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    ENV_FILE="$SCRIPT_DIR/.env"
else
    # Choose placement for new .env file
    if [ -f "$SCRIPT_DIR/prodstart.sh" ]; then
        REPO_DIR="$SCRIPT_DIR"
    else
        REPO_DIR="$(pwd)"
    fi
    ENV_FILE="$REPO_DIR/.env"
    
    # Check secret directory to copy template
    if SECRET_DIR="$(find_secret_dir)"; then
        echo "[+] Secret directory found at: $SECRET_DIR"
        for name in "env.patigon-remotemanagement" "env.patigon.remotemanagement" "env.remotemanagement"; do
            if [ -f "$SECRET_DIR/$name" ]; then
                cp "$SECRET_DIR/$name" "$ENV_FILE"
                chmod 600 "$ENV_FILE"
                echo "[+] Initialized local $ENV_FILE from secret environment $name"
                break
            fi
        done
    fi
    
    # Fallback to config.env.example if secret folder yielded nothing
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$SCRIPT_DIR/config.env.example" ]; then
            cp "$SCRIPT_DIR/config.env.example" "$ENV_FILE"
            chmod 600 "$ENV_FILE"
            echo "[+] Created local .env template at $ENV_FILE"
            echo "    Please edit this file to customize your options before running again."
            exit 0
        fi
    fi
fi

# Load local environment
if [ -f "$ENV_FILE" ]; then
    chmod 600 "$ENV_FILE"
    echo "[+] Loading environment from: $ENV_FILE"
    # shellcheck disable=SC1090
    . "$ENV_FILE"
else
    echo "[!] Warning: No .env configuration found. Using default values."
fi

# Apply default values if not configured
RUN_CLAUDE="${RUN_CLAUDE:-true}"
RUN_CODEX="${RUN_CODEX:-false}"
CLAUDE_PATH="${CLAUDE_PATH:-/root/.local/bin/claude}"
CODEX_PATH="${CODEX_PATH:-/usr/local/bin/codex}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/claude-workspace}"
CODEX_AUTH_TYPE="${CODEX_AUTH_TYPE:-subscription}"

# Helper to find executable in PATH, otherwise use the configured path
get_executable_path() {
    local configured_path="$1"
    local cmd_name="$2"
    
    if [ -x "$configured_path" ]; then
        echo "$configured_path"
        return 0
    fi
    
    if command -v "$cmd_name" >/dev/null 2>&1; then
        command -v "$cmd_name"
        return 0
    fi
    
    echo "$configured_path"
}

CLAUDE_EXEC=$(get_executable_path "$CLAUDE_PATH" "claude")
CODEX_EXEC=$(get_executable_path "$CODEX_PATH" "codex")

echo "========================================================================"
echo " Starting local development remote control instances..."
echo " - Workspace: $WORKSPACE_DIR"
echo " - Claude:    $RUN_CLAUDE (Executable: $CLAUDE_EXEC)"
echo " - Codex:     $RUN_CODEX (Executable: $CODEX_EXEC, Auth: $CODEX_AUTH_TYPE)"
echo "========================================================================"

if [ "$RUN_CLAUDE" != "true" ] && [ "$RUN_CODEX" != "true" ]; then
    echo "[-] Error: Both RUN_CLAUDE and RUN_CODEX are disabled." >&2
    echo "    Please enable at least one service in $ENV_FILE." >&2
    exit 1
fi

# Ensure workspace exists
mkdir -p "$WORKSPACE_DIR"

pids=()

# Graceful cleanup function
cleanup() {
    echo ""
    echo "========================================================================"
    echo " Shutting down all local remote-control services..."
    echo "========================================================================"
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" || true
            echo "[+] Stopped service process with PID $pid"
        fi
    done
    exit 0
}

# Trap terminal signals
trap cleanup SIGINT SIGTERM EXIT

# Start Claude Code Remote Control
if [ "$RUN_CLAUDE" = "true" ]; then
    # Validate execution
    if [ ! -x "$CLAUDE_EXEC" ] && [ "$CLAUDE_EXEC" != "claude" ]; then
        echo "[!] Error: Claude CLI is not executable or not found in PATH." >&2
        exit 1
    fi
    
    echo "[+] Starting Claude Remote Control in background..."
    (
        cd "$WORKSPACE_DIR"
        export TERM=dumb
        exec "$CLAUDE_EXEC" remote-control
    ) &
    pids+=($!)
    echo "    Claude Remote Control started (PID ${pids[-1]})"
fi

# Start Codex Remote Control
if [ "$RUN_CODEX" = "true" ]; then
    # Validate execution
    if [ ! -x "$CODEX_EXEC" ] && [ "$CODEX_EXEC" != "codex" ]; then
        echo "[!] Error: Codex CLI is not executable or not found in PATH." >&2
        exit 1
    fi
    
    if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
        if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "your_openai_api_key_here" ]; then
            echo "[-] Error: CODEX_AUTH_TYPE is set to 'api_key' but OPENAI_API_KEY is not configured in $ENV_FILE." >&2
            exit 1
        fi
    fi
    
    echo "[+] Starting Codex Remote Control in background..."
    (
        cd "$WORKSPACE_DIR"
        export TERM=dumb
        if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
            export OPENAI_API_KEY="$OPENAI_API_KEY"
        fi
        exec "$CODEX_EXEC" remote-control
    ) &
    pids+=($!)
    echo "    Codex Remote Control started (PID ${pids[-1]})"
fi

echo "========================================================================"
echo " Services are running! Streaming output logs..."
echo " Press [Ctrl+C] to stop all services."
echo "========================================================================"

# Block and wait for child processes
wait
