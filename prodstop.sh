#!/bin/bash
# ==============================================================================
# Claude Code & Codex Remote Services Stop and Cleanup Script (prodstop)
# ==============================================================================
# Stops and disables the systemd services, and removes service files.
# If called with --purge or --uninstall, cleans up all configuration and scripts.

set -e

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

# 2. Parse arguments
PURGE=false
for arg in "$@"; do
    case "$arg" in
        --purge|--uninstall)
            PURGE=true
            ;;
    esac
done

echo "========================================================================"
echo " Stopping persistent remote control services..."
echo "========================================================================"

# 3. Stop and disable claude-remote
if systemctl is-active --quiet claude-remote || systemctl is-failed --quiet claude-remote; then
    systemctl stop claude-remote || true
    echo "[+] Stopped claude-remote service."
fi
if systemctl is-enabled --quiet claude-remote; then
    systemctl disable claude-remote || true
    echo "[+] Disabled claude-remote service."
fi
if [ -f /etc/systemd/system/claude-remote.service ]; then
    rm -f /etc/systemd/system/claude-remote.service
    echo "[+] Removed /etc/systemd/system/claude-remote.service"
fi

# 4. Stop and disable codex-remote
if systemctl is-active --quiet codex-remote || systemctl is-failed --quiet codex-remote; then
    systemctl stop codex-remote || true
    echo "[+] Stopped codex-remote service."
fi
if systemctl is-enabled --quiet codex-remote; then
    systemctl disable codex-remote || true
    echo "[+] Disabled codex-remote service."
fi
if [ -f /etc/systemd/system/codex-remote.service ]; then
    rm -f /etc/systemd/system/codex-remote.service
    echo "[+] Removed /etc/systemd/system/codex-remote.service"
fi

# 5. Reload systemd configuration
echo "[+] Reloading systemd manager configuration..."
systemctl daemon-reload
systemctl reset-failed
echo "[+] Services successfully stopped and systemd definitions removed."

# 6. Purge configurations and global scripts if requested
if [ "$PURGE" = "true" ]; then
    echo ""
    echo "========================================================================"
    echo " Purging configurations and global script installations..."
    echo "========================================================================"

    # Remove global commands
    if [ -f "/usr/local/bin/prodstart" ]; then
        rm -f "/usr/local/bin/prodstart"
        echo "[+] Removed global command: /usr/local/bin/prodstart"
    fi
    if [ -f "/usr/local/bin/prodstop" ]; then
        rm -f "/usr/local/bin/prodstop"
        echo "[+] Removed global command: /usr/local/bin/prodstop"
    fi
    if [ -f "/usr/local/bin/devstart" ]; then
        rm -f "/usr/local/bin/devstart"
        echo "[+] Removed global command: /usr/local/bin/devstart"
    fi

    # Remove configuration directory
    if [ -d "/etc/claude-remote" ]; then
        rm -rf "/etc/claude-remote"
        echo "[+] Removed configuration directory: /etc/claude-remote"
    fi

    echo "[+] Uninstallation complete! All files and configurations removed."
else
    echo "------------------------------------------------------------------------"
    echo "Note: Configuration files under /etc/claude-remote/ and scripts in"
    echo "      /usr/local/bin/ have been kept."
    echo "      To completely uninstall and remove everything, run: prodstop --purge"
    echo "------------------------------------------------------------------------"
fi
echo "========================================================================"
