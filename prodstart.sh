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

# Helper to update variables in the config file
update_config_var() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    # Escape special characters for sed replacement
    local escaped_val
    escaped_val=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    if grep -q "^${key}=" "$file"; then
        if sed --version >/dev/null 2>&1; then
            sed -i "s/^${key}=.*/${key}=\"${escaped_val}\"/" "$file"
        else
            sed -i "" "s/^${key}=.*/${key}=\"${escaped_val}\"/" "$file"
        fi
    else
        echo "${key}=\"${value}\"" >> "$file"
    fi
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
        for name in "env.patigon-remotemanagement" "env.patigon.remotemanagement" "env.remotemanagement"; do
            if [ -f "$SECRET_DIR/$name" ]; then
                cp "$SECRET_DIR/$name" "$CONFIG_FILE"
                chmod 600 "$CONFIG_FILE"
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
            chmod 600 "$CONFIG_FILE"
        else
            echo "[-] Error: No configuration template found. Please create $CONFIG_FILE manually." >&2
            exit 1
        fi
    fi
fi

# Secure config file
chmod 600 "$CONFIG_FILE"

# Load current configuration
# shellcheck disable=SC1090
. "$CONFIG_FILE"

# Apply defaults if variables are missing
RUN_CLAUDE="${RUN_CLAUDE:-true}"
RUN_CODEX="${RUN_CODEX:-false}"
CLAUDE_PATH="${CLAUDE_PATH:-/root/.local/bin/claude}"
CODEX_PATH="${CODEX_PATH:-/usr/local/bin/codex}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/claude-workspace}"
CODEX_AUTH_TYPE="${CODEX_AUTH_TYPE:-subscription}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Check if script is running in an interactive terminal session
INTERACTIVE=false
if [ -t 0 ]; then
    INTERACTIVE=true
fi

# 4. Interactive Configuration Wizard
if [ "$INTERACTIVE" = "true" ]; then
    echo "========================================================================"
    echo " Claude Code & Codex Service Configuration Wizard"
    echo "========================================================================"
    echo "Welche Remote-Control Dienste möchtest du konfigurieren und aktivieren?"
    echo "1) Claude Code (aktuell aktiv: $RUN_CLAUDE)"
    echo "2) OpenAI Codex (aktuell aktiv: $RUN_CODEX)"
    echo "3) Beide"
    read -rp "Auswahl [1-3, Leerlassen für aktuelle Werte]: " SERVICE_CHOICE

    case "$SERVICE_CHOICE" in
        1)
            RUN_CLAUDE=true
            RUN_CODEX=false
            ;;
        2)
            RUN_CLAUDE=false
            RUN_CODEX=true
            ;;
        3)
            RUN_CLAUDE=true
            RUN_CODEX=true
            ;;
    esac

    update_config_var "RUN_CLAUDE" "$RUN_CLAUDE" "$CONFIG_FILE"
    update_config_var "RUN_CODEX" "$RUN_CODEX" "$CONFIG_FILE"

    # Ensure workspace folder exists
    read -rp "Workspace-Verzeichnis [$WORKSPACE_DIR]: " WS_INPUT
    if [ -n "$WS_INPUT" ]; then
        WORKSPACE_DIR="$WS_INPUT"
        update_config_var "WORKSPACE_DIR" "$WORKSPACE_DIR" "$CONFIG_FILE"
    fi
    mkdir -p "$WORKSPACE_DIR"

    # Claude CLI Install and Login check
    if [ "$RUN_CLAUDE" = "true" ]; then
        # Check install
        if [ ! -x "$CLAUDE_PATH" ] && ! command -v claude >/dev/null 2>&1; then
            echo ""
            echo "[!] Claude CLI wurde nicht auf dem System gefunden."
            read -rp "Möchtest du Claude Code jetzt automatisch installieren? [Y/n]: " INSTALL_CLAUDE
            if [[ ! "$INSTALL_CLAUDE" =~ ^[Nn]$ ]]; then
                if command -v npm >/dev/null 2>&1; then
                    npm install -g @anthropic-ai/claude-code
                else
                    curl -fsSL https://claude.ai/install.sh | sh
                fi
                
                # Re-detect path
                if command -v claude >/dev/null 2>&1; then
                    CLAUDE_PATH=$(command -v claude)
                elif [ -x "/root/.local/bin/claude" ]; then
                    CLAUDE_PATH="/root/.local/bin/claude"
                fi
                update_config_var "CLAUDE_PATH" "$CLAUDE_PATH" "$CONFIG_FILE"
            fi
        fi

        # Verify Claude Credentials
        CLAUDE_CREDENTIALS="/root/.claude/.credentials.json"
        if [ ! -f "$CLAUDE_CREDENTIALS" ]; then
            echo ""
            echo "[!] Keine Claude Code Anmeldedaten gefunden unter $CLAUDE_CREDENTIALS."
            echo "    Wir starten jetzt das Claude CLI interaktiv, damit du dich einloggen"
            echo "    und den Workspace trusten kannst."
            echo "    Bitte melde dich an und beende das CLI danach mit Ctrl+C oder 'exit'."
            echo "========================================================================"
            read -rp "Drücke [ENTER] um den Login-Vorgang zu starten..."
            
            cd "$WORKSPACE_DIR"
            # Execute claude CLI
            if [ -x "$CLAUDE_PATH" ]; then
                "$CLAUDE_PATH" || true
            elif command -v claude >/dev/null 2>&1; then
                claude || true
            else
                echo "[-] Fehler: Claude CLI konnte nicht ausgeführt werden."
            fi
            
            if [ ! -f "$CLAUDE_CREDENTIALS" ]; then
                echo "[!] Warnung: Claude Anmeldedatei wurde nicht erstellt."
                echo "    Der Remote-Dienst wird eventuell nicht funktionieren."
            else
                echo "[+] Claude Anmeldung erfolgreich abgeschlossen!"
            fi
        fi
    fi

    # Codex CLI Install, Auth and Login check
    if [ "$RUN_CODEX" = "true" ]; then
        # Check install
        if [ ! -x "$CODEX_PATH" ] && ! command -v codex >/dev/null 2>&1; then
            echo ""
            echo "[!] OpenAI Codex CLI wurde nicht auf dem System gefunden."
            read -rp "Möchtest du OpenAI Codex jetzt automatisch installieren? (Erfordert Node.js/npm) [Y/n]: " INSTALL_CODEX
            if [[ ! "$INSTALL_CODEX" =~ ^[Nn]$ ]]; then
                if command -v npm >/dev/null 2>&1; then
                    npm install -g @openai/codex
                else
                    echo "[-] Fehler: npm ist erforderlich, um @openai/codex zu installieren. Bitte installiere Node.js und npm zuerst." >&2
                    exit 1
                fi
                
                # Re-detect path
                if command -v codex >/dev/null 2>&1; then
                    CODEX_PATH=$(command -v codex)
                fi
                update_config_var "CODEX_PATH" "$CODEX_PATH" "$CONFIG_FILE"
            fi
        fi

        # Ask for Codex Auth Type
        echo ""
        echo "Welche Authentifizierungsmethode soll für Codex verwendet werden?"
        echo "1) Subscription (Abonnement - Web OAuth Login)"
        echo "2) API-Key (OpenAI API-Schlüssel)"
        read -rp "Auswahl [1-2, Leerlassen für aktuellen Wert '${CODEX_AUTH_TYPE}']: " AUTH_CHOICE

        case "$AUTH_CHOICE" in
            1) CODEX_AUTH_TYPE="subscription" ;;
            2) CODEX_AUTH_TYPE="api_key" ;;
        esac
        update_config_var "CODEX_AUTH_TYPE" "$CODEX_AUTH_TYPE" "$CONFIG_FILE"

        if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
            # API Key Input
            if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "your_openai_api_key_here" ]; then
                echo ""
                echo "[!] Kein gültiger OpenAI API-Key in der Konfiguration vorhanden."
                while true; do
                    read -rp "Bitte gib deinen OpenAI API-Key ein (z. B. sk-proj-...): " KEY_INPUT
                    if [[ "$KEY_INPUT" =~ ^sk- ]]; then
                        OPENAI_API_KEY="$KEY_INPUT"
                        update_config_var "OPENAI_API_KEY" "$OPENAI_API_KEY" "$CONFIG_FILE"
                        echo "[+] API-Key erfolgreich gespeichert!"
                        break
                    else
                        echo "[-] Ungültiges Format. Der API-Key muss mit 'sk-' beginnen. Bitte erneut versuchen."
                    fi
                done
            fi
        else
            # Verify Codex Credentials (Subscription)
            CODEX_CREDENTIALS="/root/.codex/auth.json"
            if [ ! -f "$CODEX_CREDENTIALS" ]; then
                echo ""
                echo "[!] Keine Codex Anmeldedaten gefunden unter $CODEX_CREDENTIALS."
                echo "    Wir starten jetzt das Codex CLI interaktiv, damit du dich in dein"
                echo "    ChatGPT-Konto einloggen kannst."
                echo "    Bitte melde dich an und beende das CLI danach."
                echo "========================================================================"
                read -rp "Drücke [ENTER] um den Login-Vorgang zu starten..."
                
                cd "$WORKSPACE_DIR"
                if [ -x "$CODEX_PATH" ]; then
                    "$CODEX_PATH" || true
                elif command -v codex >/dev/null 2>&1; then
                    codex || true
                else
                    echo "[-] Fehler: Codex CLI konnte nicht ausgeführt werden."
                fi
                
                if [ ! -f "$CODEX_CREDENTIALS" ]; then
                    echo "[!] Warnung: Codex Anmeldedatei wurde nicht erstellt."
                    echo "    Der Remote-Dienst wird eventuell nicht funktionieren."
                else
                    echo "[+] Codex Anmeldung erfolgreich abgeschlossen!"
                fi
            fi
        fi
    fi
    echo "========================================================================"
    echo ""
fi

# Reload configuration after wizard finishes
# shellcheck disable=SC1090
. "$CONFIG_FILE"

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
    # Resolve path
    if [ ! -x "$CLAUDE_PATH" ] && command -v claude >/dev/null 2>&1; then
        CLAUDE_PATH=$(command -v claude)
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
    # Resolve path
    if [ ! -x "$CODEX_PATH" ] && command -v codex >/dev/null 2>&1; then
        CODEX_PATH=$(command -v codex)
    fi

    # Auth configuration block
    CODEX_ENV_LINE=""
    if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
        if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "your_openai_api_key_here" ]; then
            echo "[-] Error: CODEX_AUTH_TYPE is set to 'api_key' but OPENAI_API_KEY is not configured." >&2
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
