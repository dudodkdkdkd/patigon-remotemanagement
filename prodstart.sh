#!/bin/bash
# ==============================================================================
# Claude Code & Codex Remote Services Installer and Startup Script (prodstart)
# ==============================================================================
# Operates as a persistent service manager on a Linux VPS.
# Requires root privileges to write systemd configs and global binary paths.

set -e

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

CONFIG_DIR="/etc/claude-remote"
CONFIG_FILE="$CONFIG_DIR/config.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper to resolve absolute directory path
resolve_dir() {
    local dir="$1"
    if [ -d "$dir" ]; then
        (cd "$dir" && pwd)
        return 0
    fi
    return 1
}

# Helper to find a secret directory
find_secret_dir() {
    local candidates=()
    if [ -n "${SECRET_DIR:-}" ]; then
        candidates+=("$SECRET_DIR")
    fi
    candidates+=(
        "/secret"
        "${SCRIPT_DIR}/../SECRET"
        "${SCRIPT_DIR}/../secret"
        "${SCRIPT_DIR}/../../SECRET"
        "${SCRIPT_DIR}/../../secret"
    )
    for candidate in "${candidates[@]}"; do
        if resolved="$(resolve_dir "$candidate" 2>/dev/null)"; then
            echo "$resolved"
            return 0
        fi
    done
    return 1
}

# 2. Config directory initialization
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
fi

# 3. Locate and initialize configuration
if [ ! -f "$CONFIG_FILE" ]; then
    # Try searching in secret directory (similar to Capential)
    if SECRET_DIR="$(find_secret_dir)"; then
        echo "[+] Secret directory found at: $SECRET_DIR"
        for name in "env.patigon-remotemanagement" "env.patigon.remotemanagement" "env.patigon"; do
            if [ -f "$SECRET_DIR/$name" ]; then
                cp "$SECRET_DIR/$name" "$CONFIG_FILE"
                echo "[+] Copied secret environment $name to $CONFIG_FILE"
                break
            fi
        done
    fi

    # Fallback to local configs if secret folder didn't yield a config
    if [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$SCRIPT_DIR/config.env" ]; then
            cp "$SCRIPT_DIR/config.env" "$CONFIG_FILE"
            echo "[+] Copied local config.env to $CONFIG_FILE"
        elif [ -f "$SCRIPT_DIR/config.env.example" ]; then
            cp "$SCRIPT_DIR/config.env.example" "$CONFIG_FILE"
            echo "[+] Initialized new config template at $CONFIG_FILE"
            echo "    Please edit $CONFIG_FILE to customize your options, then run 'prodstart' again."
            chmod 600 "$CONFIG_FILE"
            exit 0
        else
            echo "[-] Error: No configuration template found. Please create $CONFIG_FILE manually." >&2
            exit 1
        fi
    fi
fi

# Secure config file
chmod 600 "$CONFIG_FILE"

# 4. Load configuration
# shellcheck disable=SC1090
. "$CONFIG_FILE"

# Apply defaults if variables are missing
RUN_CLAUDE="${RUN_CLAUDE:-true}"
RUN_CODEX="${RUN_CODEX:-false}"
CLAUDE_PATH="${CLAUDE_PATH:-/root/.local/bin/claude}"
CODEX_PATH="${CODEX_PATH:-/usr/local/bin/codex}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/claude-workspace}"
CODEX_AUTH_TYPE="${CODEX_AUTH_TYPE:-subscription}"

echo "========================================================================"
echo " Starting remote services configuration..."
echo " - Workspace: $WORKSPACE_DIR"
echo " - Claude:    $RUN_CLAUDE (Path: $CLAUDE_PATH)"
echo " - Codex:     $RUN_CODEX (Path: $CODEX_PATH, Auth: $CODEX_AUTH_TYPE)"
echo "========================================================================"

# 5. Ensure workspace directory exists
mkdir -p "$WORKSPACE_DIR"

# 6. Install scripts globally for easy management
if [ "$SCRIPT_DIR" != "/usr/local/bin" ]; then
    # Install prodstart command
    cp "$SCRIPT_DIR/prodstart.sh" "/usr/local/bin/prodstart"
    chmod +x "/usr/local/bin/prodstart"
    echo "[+] Installed 'prodstart' command to /usr/local/bin/prodstart"

    # Install prodstop command
    if [ -f "$SCRIPT_DIR/prodstop.sh" ]; then
        cp "$SCRIPT_DIR/prodstop.sh" "/usr/local/bin/prodstop"
        chmod +x "/usr/local/bin/prodstop"
        echo "[+] Installed 'prodstop' command to /usr/local/bin/prodstop"
    fi

    # Install devstart command
    if [ -f "$SCRIPT_DIR/devstart.sh" ]; then
        cp "$SCRIPT_DIR/devstart.sh" "/usr/local/bin/devstart"
        chmod +x "/usr/local/bin/devstart"
        echo "[+] Installed 'devstart' command to /usr/local/bin/devstart"
    fi
fi

# 7. Claude Code Remote Control Service
if [ "$RUN_CLAUDE" = "true" ]; then
    if [ ! -x "$CLAUDE_PATH" ] && [ "$CLAUDE_PATH" != "claude" ]; then
        echo "[!] Warning: Claude executable not found or not executable at $CLAUDE_PATH"
    fi

    echo "[+] Generating /etc/systemd/system/claude-remote.service..."
    cat <<EOF > /etc/systemd/system/claude-remote.service
[Unit]
Description=Claude Code Remote Control
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORKSPACE_DIR}
Environment=HOME=/root
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=TERM=dumb
ExecStart=${CLAUDE_PATH} remote-control
Restart=always
RestartSec=5
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 600 /etc/systemd/system/claude-remote.service
    systemctl daemon-reload
    systemctl enable claude-remote.service
    systemctl restart claude-remote.service
    echo "[+] Claude Code remote-control service started & enabled."
else
    # Disable and remove service if set to false
    if systemctl is-active --quiet claude-remote; then
        systemctl stop claude-remote
        echo "[-] Stopped claude-remote service."
    fi
    if systemctl is-enabled --quiet claude-remote; then
        systemctl disable claude-remote
        echo "[-] Disabled claude-remote service."
    fi
    if [ -f /etc/systemd/system/claude-remote.service ]; then
        rm -f /etc/systemd/system/claude-remote.service
        systemctl daemon-reload
        echo "[-] Removed claude-remote.service systemd unit file."
    fi
fi

# 8. Codex Remote Control Service
if [ "$RUN_CODEX" = "true" ]; then
    if [ ! -x "$CODEX_PATH" ] && [ "$CODEX_PATH" != "codex" ]; then
        echo "[!] Warning: Codex executable not found or not executable at $CODEX_PATH"
    fi

    # Auth configuration block
    CODEX_ENV_LINE=""
    if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
        if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "your_openai_api_key_here" ]; then
            echo "[-] Error: CODEX_AUTH_TYPE is set to 'api_key' but OPENAI_API_KEY is not configured in $CONFIG_FILE." >&2
            exit 1
        fi
        CODEX_ENV_LINE="Environment=\"OPENAI_API_KEY=${OPENAI_API_KEY}\""
    fi

    echo "[+] Generating /etc/systemd/system/codex-remote.service..."
    cat <<EOF > /etc/systemd/system/codex-remote.service
[Unit]
Description=Codex CLI Remote Control
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORKSPACE_DIR}
Environment=HOME=/root
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=TERM=dumb
${CODEX_ENV_LINE}
ExecStart=${CODEX_PATH} remote-control
Restart=always
RestartSec=5
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 600 /etc/systemd/system/codex-remote.service
    systemctl daemon-reload
    systemctl enable codex-remote.service
    systemctl restart codex-remote.service
    echo "[+] Codex remote-control service started & enabled."
else
    # Disable and remove service if set to false
    if systemctl is-active --quiet codex-remote; then
        systemctl stop codex-remote
        echo "[-] Stopped codex-remote service."
    fi
    if systemctl is-enabled --quiet codex-remote; then
        systemctl disable codex-remote
        echo "[-] Disabled codex-remote service."
    fi
    if [ -f /etc/systemd/system/codex-remote.service ]; then
        rm -f /etc/systemd/system/codex-remote.service
        systemctl daemon-reload
        echo "[-] Removed codex-remote.service systemd unit file."
    fi
fi

# 9. Verify Status
echo ""
echo "========================================================================"
echo " Service Status Summary"
echo "========================================================================"

if [ "$RUN_CLAUDE" = "true" ]; then
    echo -n " claude-remote: "
    systemctl is-active claude-remote || echo "failed/inactive"
fi

if [ "$RUN_CODEX" = "true" ]; then
    echo -n " codex-remote:  "
    systemctl is-active codex-remote || echo "failed/inactive"
fi
echo "========================================================================"
echo "Done! You can check logs using: journalctl -u <service-name> -f"
echo "To run interactively in dev mode: devstart"
echo "To stop/remove production services, run: prodstop"
echo "========================================================================"
