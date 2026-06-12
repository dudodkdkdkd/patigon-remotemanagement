#!/bin/bash
# ==============================================================================
# Claude Code & Codex Remote Services Stop and Cleanup Script (prodstop)
# ==============================================================================
# Stops and disables the systemd services, and removes service files.
# If called with --purge or --uninstall, cleans up all configuration and scripts.

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

# 2. Parse arguments
PURGE=false
for arg in "$@"; do
    case "$arg" in
        --purge|--uninstall)
            PURGE=true
            ;;
    esac
done

print_header "Stopping persistent remote control services"

# 3. Stop and disable claude-remote
if systemctl is-active --quiet claude-remote || systemctl is-failed --quiet claude-remote; then
    systemctl stop claude-remote || true
    print_success "Claude-remote Dienst gestoppt."
fi
if systemctl is-enabled --quiet claude-remote; then
    systemctl disable claude-remote || true
    print_success "Claude-remote Dienst deaktiviert."
fi
if [ -f /etc/systemd/system/claude-remote.service ]; then
    rm -f /etc/systemd/system/claude-remote.service
    print_success "/etc/systemd/system/claude-remote.service entfernt."
fi

# 4. Stop and disable codex-remote
if systemctl is-active --quiet codex-remote || systemctl is-failed --quiet codex-remote; then
    systemctl stop codex-remote || true
    print_success "Codex-remote Dienst gestoppt."
fi
if systemctl is-enabled --quiet codex-remote; then
    systemctl disable codex-remote || true
    print_success "Codex-remote Dienst deaktiviert."
fi
if [ -f /etc/systemd/system/codex-remote.service ]; then
    rm -f /etc/systemd/system/codex-remote.service
    print_success "/etc/systemd/system/codex-remote.service entfernt."
fi

# 5. Reload systemd configuration
print_info "Lade systemd-Manager-Konfiguration neu..."
systemctl daemon-reload
systemctl reset-failed
print_success "Dienste erfolgreich gestoppt und Systemd-Definitionen entfernt."

# 6. Purge configurations and global scripts if requested
if [ "$PURGE" = "true" ]; then
    echo ""
    print_header "Purge: Konfigurationen und globale Installationen löschen"

    # Remove global commands
    if [ -f "/usr/local/bin/prodstart" ]; then
        rm -f "/usr/local/bin/prodstart"
        print_success "Globaler Befehl entfernt: /usr/local/bin/prodstart"
    fi
    if [ -f "/usr/local/bin/prodstop" ]; then
        rm -f "/usr/local/bin/prodstop"
        print_success "Globaler Befehl entfernt: /usr/local/bin/prodstop"
    fi
    if [ -f "/usr/local/bin/devstart" ]; then
        rm -f "/usr/local/bin/devstart"
        print_success "Globaler Befehl entfernt: /usr/local/bin/devstart"
    fi

    # Remove configuration directory
    if [ -d "/etc/claude-remote" ]; then
        rm -rf "/etc/claude-remote"
        print_success "Konfigurationsverzeichnis entfernt: /etc/claude-remote"
    fi

    print_success "Deinstallation abgeschlossen! Alle Dateien und Einstellungen wurden gelöscht."
else
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    print_info "Hinweis: Konfigurationsdateien unter /etc/claude-remote/ und Skripte"
    print_info "         in /usr/local/bin/ wurden beibehalten."
    print_info "         Um alles vollständig zu deinstallieren, führe aus: ${BOLD}prodstop --purge${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
fi
echo -e "${BCYAN}========================================================================${NC}"
