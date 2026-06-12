#!/bin/bash
# ==============================================================================
# Claude Code & Codex Remote Services Installer and Startup Script (prodstart)
# ==============================================================================
# Operates as a persistent service manager on a Linux VPS.
# Requires root privileges to write systemd configs and global binary paths.

set -e

# ANSI Color Codes for premium CLI experience
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

# Helper functions for structured output
print_header() {
    local title="$1"
    echo -e "${BCYAN}┌──────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BCYAN}│${NC}  ${BWHITE}%-64s${NC}  ${BCYAN}│${NC}\n" "$title"
    echo -e "${BCYAN}└──────────────────────────────────────────────────────────────────────┘${NC}"
}

print_step() {
    local num="$1"
    local desc="$2"
    echo -e "\n${BBLUE}[Step $num]${NC} ${BWHITE}$desc${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
}

print_success() {
    echo -e "${BGREEN}✔ $1${NC}"
}

print_warning() {
    echo -e "${BYELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${BRED}✘ $1${NC}" >&2
}

print_info() {
    echo -e "${BCYAN}ℹ $1${NC}"
}

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte mit sudo ausführen."
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
    print_header "Claude Code & Codex Configuration Wizard"
    
    # Check actual systemd service status
    CLAUDE_SERVICE_RUNNING=false
    if systemctl is-active --quiet claude-remote 2>/dev/null; then
        CLAUDE_SERVICE_RUNNING=true
    fi
    CODEX_SERVICE_RUNNING=false
    if systemctl is-active --quiet codex-remote 2>/dev/null; then
        CODEX_SERVICE_RUNNING=true
    fi

    claude_status="${RED}inaktiv${NC}"
    if [ "$CLAUDE_SERVICE_RUNNING" = "true" ]; then
        claude_status="${BGREEN}aktiv (läuft)${NC}"
    elif [ "$RUN_CLAUDE" = "true" ]; then
        claude_status="${BYELLOW}inaktiv (aktiviert in Konfig)${NC}"
    fi

    codex_status="${RED}inaktiv${NC}"
    if [ "$CODEX_SERVICE_RUNNING" = "true" ]; then
        codex_status="${BGREEN}aktiv (läuft)${NC}"
    elif [ "$RUN_CODEX" = "true" ]; then
        codex_status="${BYELLOW}inaktiv (aktiviert in Konfig)${NC}"
    fi

    print_step "1" "Dienste auswählen"
    echo -e "Welche Remote-Control Dienste möchtest du konfigurieren und aktivieren?"
    echo ""
    echo -e "  ${BCYAN}[1]${NC} Claude Code    (Aktuell: ${claude_status})"
    echo -e "  ${BCYAN}[2]${NC} OpenAI Codex  (Aktuell: ${codex_status})"
    echo -e "  ${BCYAN}[3]${NC} Beide aktivieren"
    echo ""
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

    print_step "2" "Workspace einrichten"
    echo -e "Bitte lege das Arbeitsverzeichnis für die KI fest:"
    read -rp "Workspace-Verzeichnis [$WORKSPACE_DIR]: " WS_INPUT
    if [ -n "$WS_INPUT" ]; then
        WORKSPACE_DIR="$WS_INPUT"
        update_config_var "WORKSPACE_DIR" "$WORKSPACE_DIR" "$CONFIG_FILE"
    fi
    mkdir -p "$WORKSPACE_DIR"
    print_success "Workspace-Verzeichnis bereitgestellt: $WORKSPACE_DIR"

    # Claude CLI Install and Login check
    if [ "$RUN_CLAUDE" = "true" ]; then
        print_step "3" "Claude Code einrichten"
        
        # Check install
        if [ ! -x "$CLAUDE_PATH" ] && ! command -v claude >/dev/null 2>&1; then
            print_warning "Claude CLI wurde nicht auf dem System gefunden."
            read -rp "Möchtest du Claude Code jetzt automatisch installieren? [Y/n]: " INSTALL_CLAUDE
            if [[ ! "$INSTALL_CLAUDE" =~ ^[Nn]$ ]]; then
                print_info "Installiere Claude Code..."
                if command -v npm >/dev/null 2>&1; then
                    npm install -g @anthropic-ai/claude-code
                else
                    curl -fsSL https://claude.ai/install.sh | sh
                fi
                
                # Re-detect path
                if command -v claude >/dev/null 2>&1; then
                    CLAUDE_PATH=$(command -v claude)
                elif [ -x "$HOME/.local/bin/claude" ]; then
                    CLAUDE_PATH="$HOME/.local/bin/claude"
                fi
                update_config_var "CLAUDE_PATH" "$CLAUDE_PATH" "$CONFIG_FILE"
                print_success "Claude Code installiert unter: $CLAUDE_PATH"
            fi
        else
            # Resolve generic command
            if [ ! -x "$CLAUDE_PATH" ] && command -v claude >/dev/null 2>&1; then
                CLAUDE_PATH=$(command -v claude)
                update_config_var "CLAUDE_PATH" "$CLAUDE_PATH" "$CONFIG_FILE"
            fi
            print_info "Claude Code gefunden unter: $CLAUDE_PATH"
        fi

        # Verify Claude Credentials
        CLAUDE_CREDENTIALS="$HOME/.claude/.credentials.json"
        if [ ! -f "$CLAUDE_CREDENTIALS" ]; then
            print_warning "Keine Claude Code Anmeldedaten gefunden unter $CLAUDE_CREDENTIALS."
            echo -e "Wir starten jetzt die Anmeldung für Claude Code."
            read -rp "Drücke [ENTER] um den Login-Vorgang zu starten..."
            
            echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
            # Execute claude login flow
            if [ -x "$CLAUDE_PATH" ]; then
                "$CLAUDE_PATH" auth login || true
            elif command -v claude >/dev/null 2>&1; then
                claude auth login || true
            else
                print_error "Claude CLI konnte nicht ausgeführt werden."
            fi
            echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
            
            if [ ! -f "$CLAUDE_CREDENTIALS" ]; then
                print_warning "Claude Anmeldedatei wurde nicht erstellt."
                print_warning "Der Remote-Dienst wird eventuell nicht funktionieren."
            else
                print_success "Claude Anmeldung erfolgreich abgeschlossen!"
            fi
        else
            print_success "Claude Anmeldung ist bereits aktiv."
        fi
    fi

    # Codex CLI Install, Auth and Login check
    if [ "$RUN_CODEX" = "true" ]; then
        print_step "4" "OpenAI Codex einrichten"
        
        # Check install
        if [ ! -x "$CODEX_PATH" ] && ! command -v codex >/dev/null 2>&1; then
            print_warning "OpenAI Codex CLI wurde nicht auf dem System gefunden."
            read -rp "Möchtest du OpenAI Codex jetzt automatisch installieren? (Erfordert Node.js/npm) [Y/n]: " INSTALL_CODEX
            if [[ ! "$INSTALL_CODEX" =~ ^[Nn]$ ]]; then
                print_info "Installiere @openai/codex..."
                if command -v npm >/dev/null 2>&1; then
                    npm install -g @openai/codex
                else
                    print_error "npm ist erforderlich, um @openai/codex zu installieren. Bitte installiere Node.js."
                    exit 1
                fi
                
                # Re-detect path
                if command -v codex >/dev/null 2>&1; then
                    CODEX_PATH=$(command -v codex)
                fi
                update_config_var "CODEX_PATH" "$CODEX_PATH" "$CONFIG_FILE"
                print_success "Codex installiert unter: $CODEX_PATH"
            fi
        else
            # Resolve generic command
            if [ ! -x "$CODEX_PATH" ] && command -v codex >/dev/null 2>&1; then
                CODEX_PATH=$(command -v codex)
                update_config_var "CODEX_PATH" "$CODEX_PATH" "$CONFIG_FILE"
            fi
            print_info "OpenAI Codex gefunden unter: $CODEX_PATH"
        fi

        # Ask for Codex Auth Type
        echo -e "\nAuthentifizierungsmethode für Codex wählen:"
        echo -e "  ${BCYAN}[1]${NC} Subscription (Abonnement - Web OAuth Login) - ${BOLD}Empfohlen${NC}"
        echo -e "  ${BCYAN}[2]${NC} API-Key (OpenAI API-Schlüssel)"
        echo ""
        read -rp "Auswahl [1-2, Leerlassen für aktuellen Wert '${CODEX_AUTH_TYPE}']: " AUTH_CHOICE

        case "$AUTH_CHOICE" in
            1) CODEX_AUTH_TYPE="subscription" ;;
            2) CODEX_AUTH_TYPE="api_key" ;;
        esac
        update_config_var "CODEX_AUTH_TYPE" "$CODEX_AUTH_TYPE" "$CONFIG_FILE"

        if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
            # API Key Input
            if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "your_openai_api_key_here" ]; then
                print_warning "Kein gültiger OpenAI API-Schlüssel in der Konfiguration vorhanden."
                while true; do
                    read -rp "Bitte gib deinen OpenAI API-Schlüssel ein (z. B. sk-proj-...): " KEY_INPUT
                    if [[ "$KEY_INPUT" =~ ^sk- ]]; then
                        OPENAI_API_KEY="$KEY_INPUT"
                        update_config_var "OPENAI_API_KEY" "$OPENAI_API_KEY" "$CONFIG_FILE"
                        print_success "API-Schlüssel erfolgreich gespeichert!"
                        break
                    else
                        print_error "Ungültiges Format. Der Schlüssel muss mit 'sk-' beginnen."
                    fi
                done
            else
                print_success "API-Schlüssel ist bereits konfiguriert."
            fi
        else
            # Verify Codex Credentials (Subscription)
            CODEX_CREDENTIALS="$HOME/.codex/auth.json"
            if [ ! -f "$CODEX_CREDENTIALS" ]; then
                print_warning "Keine Codex Anmeldedaten gefunden unter $CODEX_CREDENTIALS."
                echo -e "Wir starten jetzt die Anmeldung für OpenAI Codex."
                read -rp "Drücke [ENTER] um den Login-Vorgang zu starten..."
                
                echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
                if [ -x "$CODEX_PATH" ]; then
                    "$CODEX_PATH" login --device-auth || true
                elif command -v codex >/dev/null 2>&1; then
                    codex login --device-auth || true
                else
                    print_error "Codex CLI konnte nicht ausgeführt werden."
                fi
                echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
                
                if [ ! -f "$CODEX_CREDENTIALS" ]; then
                    print_warning "Codex Anmeldedatei wurde nicht erstellt."
                    print_warning "Der Remote-Dienst wird eventuell nicht funktionieren."
                else
                    print_success "Codex Anmeldung erfolgreich abgeschlossen!"
                fi
            else
                print_success "Codex Anmeldung ist bereits aktiv."
            fi
        fi
    fi
    echo -e "${BCYAN}========================================================================${NC}"
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

print_step "5" "Dienste konfigurieren & starten"
echo -e "  Workspace: ${BLUE}$WORKSPACE_DIR${NC}"
echo -e "  Claude:    $([ "$RUN_CLAUDE" = "true" ] && echo -e "${GREEN}aktiv${NC} (${CYAN}$CLAUDE_PATH${NC})" || echo -e "${RED}inaktiv${NC}")"
echo -e "  Codex:     $([ "$RUN_CODEX" = "true" ] && echo -e "${GREEN}aktiv${NC} (${CYAN}$CODEX_PATH${NC}, Auth: $CODEX_AUTH_TYPE)" || echo -e "${RED}inaktiv${NC}")"
echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"

# 5. Ensure workspace directory exists
mkdir -p "$WORKSPACE_DIR"

# 6. Install scripts globally for easy management
if [ "$SCRIPT_DIR" != "/usr/local/bin" ]; then
    # Install prodstart command
    cp "$SCRIPT_DIR/prodstart.sh" "/usr/local/bin/prodstart"
    chmod +x "/usr/local/bin/prodstart"
    print_success "Globaler Befehl installiert: /usr/local/bin/prodstart"

    # Install prodstop command
    if [ -f "$SCRIPT_DIR/prodstop.sh" ]; then
        cp "$SCRIPT_DIR/prodstop.sh" "/usr/local/bin/prodstop"
        chmod +x "/usr/local/bin/prodstop"
        print_success "Globaler Befehl installiert: /usr/local/bin/prodstop"
    fi

    # Install devstart command
    if [ -f "$SCRIPT_DIR/devstart.sh" ]; then
        cp "$SCRIPT_DIR/devstart.sh" "/usr/local/bin/devstart"
        chmod +x "/usr/local/bin/devstart"
        print_success "Globaler Befehl installiert: /usr/local/bin/devstart"
    fi
fi

# 7. Claude Code Remote Control Service
if [ "$RUN_CLAUDE" = "true" ]; then
    # Resolve path
    if [ ! -x "$CLAUDE_PATH" ] && command -v claude >/dev/null 2>&1; then
        CLAUDE_PATH=$(command -v claude)
    fi

    print_info "Generiere /etc/systemd/system/claude-remote.service..."
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
    print_success "Claude Code remote-control Dienst gestartet & aktiviert."
else
    # Disable and remove service if set to false
    if systemctl is-active --quiet claude-remote; then
        systemctl stop claude-remote
        print_info "Claude-remote Dienst gestoppt."
    fi
    if systemctl is-enabled --quiet claude-remote; then
        systemctl disable claude-remote
        print_info "Claude-remote Dienst deaktiviert."
    fi
    if [ -f /etc/systemd/system/claude-remote.service ]; then
        rm -f /etc/systemd/system/claude-remote.service
        systemctl daemon-reload
        print_info "claude-remote.service systemd-Unit-Datei entfernt."
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
            print_error "CODEX_AUTH_TYPE ist 'api_key', aber OPENAI_API_KEY ist nicht konfiguriert."
            exit 1
        fi
        CODEX_ENV_LINE="Environment=\"OPENAI_API_KEY=${OPENAI_API_KEY}\""
    fi

    print_info "Generiere /etc/systemd/system/codex-remote.service..."
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
    print_success "Codex remote-control Dienst gestartet & aktiviert."
else
    # Disable and remove service if set to false
    if systemctl is-active --quiet codex-remote; then
        systemctl stop codex-remote
        print_info "Codex-remote Dienst gestoppt."
    fi
    if systemctl is-enabled --quiet codex-remote; then
        systemctl disable codex-remote
        print_info "Codex-remote Dienst deaktiviert."
    fi
    if [ -f /etc/systemd/system/codex-remote.service ]; then
        rm -f /etc/systemd/system/codex-remote.service
        systemctl daemon-reload
        print_info "codex-remote.service systemd-Unit-Datei entfernt."
    fi
fi

# 9. Verify Status
echo ""
print_header "Dienst-Status Übersicht"

if [ "$RUN_CLAUDE" = "true" ]; then
    echo -n "  claude-remote: "
    if systemctl is-active --quiet claude-remote; then
        echo -e "${BGREEN}aktiv (running)${NC}"
    else
        echo -e "${BRED}inaktiv / fehlerhaft${NC}"
    fi
fi

if [ "$RUN_CODEX" = "true" ]; then
    echo -n "  codex-remote:  "
    if systemctl is-active --quiet codex-remote; then
        echo -e "${BGREEN}aktiv (running)${NC}"
    else
        echo -e "${BRED}inaktiv / fehlerhaft${NC}"
    fi
fi
echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
echo -e "${GREEN}Setup erfolgreich abgeschlossen!${NC}"
echo -e "Logs ansehen:               ${BOLD}journalctl -u <dienst-name> -f${NC}"
echo -e "Interaktiv in Dev starten:  ${BOLD}devstart${NC}"
echo -e "Produktionsdienste stoppen: ${BOLD}prodstop${NC}"
echo -e "${BCYAN}========================================================================${NC}"
