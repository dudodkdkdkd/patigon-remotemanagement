#!/bin/bash
# ==============================================================================
# Claude Code & Codex Local Development Script (devstart)
# ==============================================================================
# Runs remote control instances interactively in the foreground.
# Prioritizes local project environment and resolves CLI paths using system PATH.

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

# Root Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte mit sudo ausführen."
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
    print_info "Lade Umgebung aus: $ENV_FILE"
    # shellcheck disable=SC1090
    . "$ENV_FILE"
else
    print_warning "Keine .env-Konfigurationsdatei gefunden. Nutze Standardwerte."
fi

# Apply default values if not configured
RUN_CLAUDE="${RUN_CLAUDE:-true}"
RUN_CODEX="${RUN_CODEX:-false}"
CLAUDE_PATH="${CLAUDE_PATH:-/root/.local/bin/claude}"
CODEX_PATH="${CODEX_PATH:-/usr/local/bin/codex}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/opt/ai-workspace}"
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

# Verify Claude Credentials
if [ "$RUN_CLAUDE" = "true" ]; then
    CLAUDE_CREDENTIALS="$HOME/.claude/.credentials.json"
    if [ ! -f "$CLAUDE_CREDENTIALS" ]; then
        print_warning "Keine Claude Code Anmeldedaten gefunden unter $CLAUDE_CREDENTIALS."
        echo -e "Wir starten jetzt die Anmeldung für Claude Code."
        read -rp "Drücke [ENTER] um den Login-Vorgang zu starten..."
        
        echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
        if [ -x "$CLAUDE_EXEC" ]; then
            "$CLAUDE_EXEC" auth login || true
        elif command -v claude >/dev/null 2>&1; then
            claude auth login || true
        else
            print_error "Claude CLI konnte nicht ausgeführt werden."
        fi
        echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
        
        if [ ! -f "$CLAUDE_CREDENTIALS" ]; then
            print_error "Claude Anmeldedatei wurde nicht erstellt. Abbruch."
            exit 1
        fi
        print_success "Claude Anmeldung erfolgreich abgeschlossen!"
    fi
fi

# Verify Codex Credentials
if [ "$RUN_CODEX" = "true" ] && [ "$CODEX_AUTH_TYPE" = "subscription" ]; then
    CODEX_CREDENTIALS="$HOME/.codex/auth.json"
    if [ ! -f "$CODEX_CREDENTIALS" ]; then
        print_warning "Keine Codex Anmeldedaten gefunden unter $CODEX_CREDENTIALS."
        echo -e "Wir starten jetzt die Anmeldung für OpenAI Codex."
        read -rp "Drücke [ENTER] um den Login-Vorgang zu starten..."
        
        echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
        if [ -x "$CODEX_EXEC" ]; then
            "$CODEX_EXEC" login --device-auth || true
        elif command -v codex >/dev/null 2>&1; then
            codex login --device-auth || true
        else
            print_error "Codex CLI konnte nicht ausgeführt werden."
        fi
        echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
        
        if [ ! -f "$CODEX_CREDENTIALS" ]; then
            print_error "Codex Anmeldedatei wurde nicht erstellt. Abbruch."
            exit 1
        fi
        print_success "Codex Anmeldung erfolgreich abgeschlossen!"
    fi
fi

print_header "Start dev remote control services"
print_step "1" "Dienste verifizieren & starten"
echo -e "  Workspace: ${BLUE}$WORKSPACE_DIR${NC}"
echo -e "  Claude:    $([ "$RUN_CLAUDE" = "true" ] && echo -e "${GREEN}aktiv${NC} (${CYAN}$CLAUDE_EXEC${NC})" || echo -e "${RED}inaktiv${NC}")"
echo -e "  Codex:     $([ "$RUN_CODEX" = "true" ] && echo -e "${GREEN}aktiv${NC} (${CYAN}$CODEX_EXEC${NC}, Auth: $CODEX_AUTH_TYPE)" || echo -e "${RED}inaktiv${NC}")"
echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"

if [ "$RUN_CLAUDE" != "true" ] && [ "$RUN_CODEX" != "true" ]; then
    print_error "Beide Dienste (RUN_CLAUDE und RUN_CODEX) sind deaktiviert."
    print_error "Bitte aktiviere mindestens einen Dienst in $ENV_FILE."
    exit 1
fi

# Ensure workspace exists
mkdir -p "$WORKSPACE_DIR"

pids=()

# Graceful cleanup function
cleanup() {
    echo ""
    print_header "Beende alle lokalen Dienste..."
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" || true
            print_success "Dienst mit PID $pid gestoppt"
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
        print_error "Claude CLI ist nicht ausführbar oder wurde im PATH nicht gefunden."
        exit 1
    fi
    
    print_info "Starte Claude Remote Control im Hintergrund..."
    (
        cd "$WORKSPACE_DIR"
        export TERM=dumb
        exec "$CLAUDE_EXEC" remote-control
    ) &
    pids+=($!)
    print_success "Claude Remote Control gestartet (PID ${pids[-1]})"
fi

# Start Codex Remote Control
if [ "$RUN_CODEX" = "true" ]; then
    # Validate execution
    if [ ! -x "$CODEX_EXEC" ] && [ "$CODEX_EXEC" != "codex" ]; then
        print_error "Codex CLI ist nicht ausführbar oder wurde im PATH nicht gefunden."
        exit 1
    fi
    
    if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
        if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "your_openai_api_key_here" ]; then
            print_error "CODEX_AUTH_TYPE ist 'api_key', aber OPENAI_API_KEY ist in $ENV_FILE nicht konfiguriert."
            exit 1
        fi
    fi
    
    print_info "Starte Codex Remote Control im Hintergrund..."
    (
        cd "$WORKSPACE_DIR"
        export TERM=dumb
        if [ "$CODEX_AUTH_TYPE" = "api_key" ]; then
            export OPENAI_API_KEY="$OPENAI_API_KEY"
        fi
        exec "$CODEX_EXEC" remote-control
    ) &
    pids+=($!)
    print_success "Codex Remote Control gestartet (PID ${pids[-1]})"
fi

echo -e "${BCYAN}========================================================================${NC}"
echo -e "  ${BGREEN}Dienste sind aktiv!${NC} Logs werden gestreamt..."
echo -e "  Drücke ${BOLD}[Ctrl+C]${NC} zum Beenden aller Hintergrundprozesse."
echo -e "${BCYAN}========================================================================${NC}"

# Block and wait for child processes
wait
