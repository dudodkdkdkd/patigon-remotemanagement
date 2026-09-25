#!/bin/bash
# ==============================================================================
# Claude Code, Codex & Desktop Commander Remote Services Stop Script (prodstop)
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

# Check if script is running in an interactive terminal session
INTERACTIVE=false
if [ -t 0 ]; then
    INTERACTIVE=true
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

STOP_SERVICES=true
REMOVE_GLOBAL_COMMANDS=false
REMOVE_CONFIG=false
UNINSTALL_CLI_TOOLS=false
REMOVE_DESKTOP_COMMANDER_INSTALL=false
REMOVE_DESKTOP_COMMANDER_CREDENTIALS=false
REMOVE_DESKTOP_COMMANDER_USER=false

DESKTOP_COMMANDER_ISOLATED_USER=false
DESKTOP_COMMANDER_USER=patigon-remote
DESKTOP_COMMANDER_HOME=/var/lib/patigon-remotemanagement
if [ -f /etc/claude-remote/config.env ]; then
    # shellcheck disable=SC1091
    . /etc/claude-remote/config.env
fi

# Dynamic model (default): DESKTOP_COMMANDER_USER/HOME are never persisted to
# config.env by prodstart, so resolve the same way it does - from the user
# who ran sudo - so credential cleanup below targets the right home.
if [ "$DESKTOP_COMMANDER_ISOLATED_USER" != "true" ] &&
   [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] &&
   id -u "$SUDO_USER" >/dev/null 2>&1; then
    DESKTOP_COMMANDER_USER="$SUDO_USER"
    resolved_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    [ -n "$resolved_home" ] && DESKTOP_COMMANDER_HOME="$resolved_home"
fi

if [ "$PURGE" = "true" ]; then
    REMOVE_GLOBAL_COMMANDS=true
    REMOVE_CONFIG=true
    UNINSTALL_CLI_TOOLS=true
    if [ "$INTERACTIVE" = "true" ]; then
        read -rp "Desktop-Commander-Installation entfernen? [y/N]: " CHOICE_DC_INSTALL
        [[ "$CHOICE_DC_INSTALL" =~ ^[Yy]$ ]] && REMOVE_DESKTOP_COMMANDER_INSTALL=true
        read -rp "Lokale Desktop-Commander-Device-Credentials entfernen? [y/N]: " CHOICE_DC_CREDENTIALS
        [[ "$CHOICE_DC_CREDENTIALS" =~ ^[Yy]$ ]] && REMOVE_DESKTOP_COMMANDER_CREDENTIALS=true
        # Only the legacy isolated model has a separate service account to
        # remove. In the default dynamic-user model DESKTOP_COMMANDER_USER is
        # the real, currently-logged-in person's own login - never offer or
        # allow deleting that account here.
        if [ "$DESKTOP_COMMANDER_ISOLATED_USER" = "true" ]; then
            read -rp "Service-User $DESKTOP_COMMANDER_USER entfernen? [y/N]: " CHOICE_DC_USER
            [[ "$CHOICE_DC_USER" =~ ^[Yy]$ ]] && REMOVE_DESKTOP_COMMANDER_USER=true
        fi
    fi
elif [ "$INTERACTIVE" = "true" ]; then
    print_header "Deinstallations-Assistent"
    echo -e "Bitte entscheide der Reihe nach, was deinstalliert/entfernt werden soll:"
    echo ""

    read -rp "  1. Hintergrunddienste stoppen und Systemd-Dateien löschen? [Y/n]: " CHOICE_SERVICES
    if [[ "$CHOICE_SERVICES" =~ ^[Nn]$ ]]; then
        STOP_SERVICES=false
    fi

    read -rp "  2. CLI-Tools (Claude Code, OpenAI Codex) deinstallieren & Anmeldedaten löschen? [y/N]: " CHOICE_CLI
    if [[ "$CHOICE_CLI" =~ ^[Yy]$ ]]; then
        UNINSTALL_CLI_TOOLS=true
    fi

    read -rp "  3. Globale Befehls-Verknüpfungen aus /usr/local/bin entfernen? [y/N]: " CHOICE_COMMANDS
    if [[ "$CHOICE_COMMANDS" =~ ^[Yy]$ ]]; then
        REMOVE_GLOBAL_COMMANDS=true
    fi

    read -rp "  4. Konfigurationsverzeichnis /etc/claude-remote (mit config.env) löschen? [y/N]: " CHOICE_CONFIG
    if [[ "$CHOICE_CONFIG" =~ ^[Yy]$ ]]; then
        REMOVE_CONFIG=true
    fi
    echo ""
fi

# We can execute the steps now

if [ "$STOP_SERVICES" = "true" ]; then
    print_header "Stopping persistent remote control services"
    
    # 3. Stop and disable claude-remote
    if systemctl is-active --quiet claude-remote 2>/dev/null || systemctl is-failed --quiet claude-remote 2>/dev/null; then
        systemctl stop claude-remote || true
        print_success "Claude-remote Dienst gestoppt."
    fi
    if systemctl is-enabled --quiet claude-remote 2>/dev/null; then
        systemctl disable claude-remote || true
        print_success "Claude-remote Dienst deaktiviert."
    fi
    if [ -f /etc/systemd/system/claude-remote.service ]; then
        rm -f /etc/systemd/system/claude-remote.service
        print_success "/etc/systemd/system/claude-remote.service entfernt."
    fi

    # 4. Stop and disable codex-remote
    if systemctl is-active --quiet codex-remote 2>/dev/null || systemctl is-failed --quiet codex-remote 2>/dev/null; then
        systemctl stop codex-remote || true
        print_success "Codex-remote Dienst gestoppt."
    fi
    if systemctl is-enabled --quiet codex-remote 2>/dev/null; then
        systemctl disable codex-remote || true
        print_success "Codex-remote Dienst deaktiviert."
    fi
    if [ -f /etc/systemd/system/codex-remote.service ]; then
        rm -f /etc/systemd/system/codex-remote.service
        print_success "/etc/systemd/system/codex-remote.service entfernt."
    fi

    if systemctl is-active --quiet desktop-commander-remote 2>/dev/null || systemctl is-failed --quiet desktop-commander-remote 2>/dev/null; then
        systemctl stop desktop-commander-remote || true
        print_success "Desktop-Commander-Dienst gestoppt."
    fi
    if systemctl is-enabled --quiet desktop-commander-remote 2>/dev/null; then
        systemctl disable desktop-commander-remote || true
        print_success "Desktop-Commander-Dienst deaktiviert."
    fi
    if [ -f /etc/systemd/system/desktop-commander-remote.service ]; then
        rm -f /etc/systemd/system/desktop-commander-remote.service
        print_success "/etc/systemd/system/desktop-commander-remote.service entfernt."
    fi

    if systemctl is-enabled --quiet codex-release-cleanup.timer 2>/dev/null; then
        systemctl disable --now codex-release-cleanup.timer || true
        print_success "Codex-Release-Cleanup-Timer deaktiviert."
    fi
    if [ -f /etc/systemd/system/codex-release-cleanup.service ] ||
       [ -f /etc/systemd/system/codex-release-cleanup.timer ]; then
        rm -f \
            /etc/systemd/system/codex-release-cleanup.service \
            /etc/systemd/system/codex-release-cleanup.timer
        print_success "Codex-Release-Cleanup-Units entfernt."
    fi

    # 5. Reload systemd configuration
    print_info "Lade systemd-Manager-Konfiguration neu..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true
    print_success "Dienste erfolgreich gestoppt und Systemd-Definitionen entfernt."

    print_info "Die Dienst-Auswahl in config.env bleibt für den nächsten prodstart erhalten."
fi

if [ "$PURGE" = "true" ]; then
    if [ "$REMOVE_DESKTOP_COMMANDER_INSTALL" = "true" ]; then
        if command -v npm >/dev/null 2>&1; then
            npm --prefix /usr/local uninstall -g @wonderwhy-er/desktop-commander
            print_success "Desktop Commander deinstalliert."
        else
            print_warning "npm fehlt; Desktop Commander konnte nicht deinstalliert werden."
        fi
    fi
    if [ "$REMOVE_DESKTOP_COMMANDER_CREDENTIALS" = "true" ]; then
        # Scoped to the .desktop-commander-device subfolder only, and only
        # when DESKTOP_COMMANDER_HOME matches that user's actual passwd home
        # - safe to run against a real person's home directory too.
        if [ -n "$DESKTOP_COMMANDER_HOME" ] &&
           [ "$DESKTOP_COMMANDER_HOME" != "/" ] &&
           [[ "$DESKTOP_COMMANDER_HOME" != *"/../"* ]] &&
           [[ "$DESKTOP_COMMANDER_HOME" != *"/.." ]] &&
           [ "$DESKTOP_COMMANDER_HOME" = "$(readlink -m "$DESKTOP_COMMANDER_HOME")" ] &&
           [ "$(getent passwd "$DESKTOP_COMMANDER_USER" 2>/dev/null | cut -d: -f6)" = "$DESKTOP_COMMANDER_HOME" ]; then
            rm -rf "$DESKTOP_COMMANDER_HOME/.desktop-commander-device"
            print_success "Lokale Desktop-Commander-Device-Credentials entfernt."
        else
            print_error "Unsicherer Desktop-Commander-Home-Pfad; Credentials nicht entfernt."
        fi
    fi
    if [ "$REMOVE_DESKTOP_COMMANDER_USER" = "true" ] &&
       [ "$DESKTOP_COMMANDER_ISOLATED_USER" = "true" ] &&
       id -u "$DESKTOP_COMMANDER_USER" >/dev/null 2>&1; then
        # Extra hard gate: only ever userdel the dedicated legacy service
        # account, never the real, dynamically-resolved login user.
        if [[ "$DESKTOP_COMMANDER_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] &&
           [ "$DESKTOP_COMMANDER_USER" != root ] &&
           [[ "$DESKTOP_COMMANDER_HOME" =~ ^/var/lib/[a-zA-Z0-9._/-]+$ ]] &&
           [ "$(getent passwd "$DESKTOP_COMMANDER_USER" | cut -d: -f6)" = "$DESKTOP_COMMANDER_HOME" ]; then
            userdel "$DESKTOP_COMMANDER_USER"
            print_success "Service-User $DESKTOP_COMMANDER_USER entfernt (Home-Verzeichnis bleibt erhalten)."
        else
            print_error "Service-User/Home stimmen nicht mit der Konfiguration überein; Benutzer nicht entfernt."
        fi
    fi
fi

if [ "$UNINSTALL_CLI_TOOLS" = "true" ]; then
    print_header "Deinstalliere CLI-Tools & Anmeldedaten"
    if command -v npm >/dev/null 2>&1; then
        print_info "Deinstalliere Claude Code NPM-Paket..."
        npm uninstall -g @anthropic-ai/claude-code || true
        print_info "Deinstalliere OpenAI Codex NPM-Paket..."
        npm uninstall -g @openai/codex || true
    fi
    
    if [ -d "$HOME/.claude" ]; then
        rm -rf "$HOME/.claude"
        print_success "Claude-Konfigurationsverzeichnis entfernt: $HOME/.claude"
    fi
    if [ -f "$HOME/.local/bin/claude" ]; then
        rm -f "$HOME/.local/bin/claude"
        print_success "Claude-Binary entfernt: $HOME/.local/bin/claude"
    fi
    if [ -d "$HOME/.codex" ]; then
        rm -rf "$HOME/.codex"
        print_success "Codex-Konfigurationsverzeichnis entfernt: $HOME/.codex"
    fi
fi

if [ "$REMOVE_GLOBAL_COMMANDS" = "true" ]; then
    print_header "Entferne globale Befehle"
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
    if [ -f "/usr/local/bin/prodstart-isolated-desktop-commander" ]; then
        rm -f "/usr/local/bin/prodstart-isolated-desktop-commander"
        print_success "Globaler Befehl entfernt: /usr/local/bin/prodstart-isolated-desktop-commander"
    fi
fi

if [ "$PURGE" = "true" ] && [ -d "/usr/local/lib/patigon-remotemanagement" ]; then
    rm -rf "/usr/local/lib/patigon-remotemanagement"
    print_success "Installierte Remotemanagement-Hilfsskripte entfernt."
fi

if [ "$REMOVE_CONFIG" = "true" ]; then
    print_header "Entferne Konfigurationsdateien"
    if [ -d "/etc/claude-remote" ]; then
        rm -rf "/etc/claude-remote"
        print_success "Konfigurationsverzeichnis entfernt: /etc/claude-remote"
    fi
fi

echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
print_success "Bereinigung erfolgreich abgeschlossen!"
if [ "$REMOVE_CONFIG" = "false" ] || [ "$REMOVE_GLOBAL_COMMANDS" = "false" ] || [ "$UNINSTALL_CLI_TOOLS" = "false" ]; then
    print_info "Hinweis: Einige Komponenten wurden vereinbarungsgemäß behalten."
    print_info "         Um alles vollständig zu deinstallieren, führe aus: ${BOLD}prodstop --purge${NC}"
fi
echo -e "${BCYAN}========================================================================${NC}"
