#!/bin/bash
# ==============================================================================
# Opt-in: install Desktop Commander with the legacy isolated service-account
# model instead of the default dynamic-user model.
# ==============================================================================
# Default (plain `prodstart`): the Desktop Commander service runs as whoever
# ran `sudo prodstart` - no dedicated account, no shared group, no curated
# workspace ACLs.
#
# This script instead sets DESKTOP_COMMANDER_ISOLATED_USER=true and installs
# the old model: a dedicated, less-privileged system account
# (DESKTOP_COMMANDER_USER, default patigon-remote) with its own home
# (DESKTOP_COMMANDER_HOME), granted access only to WORKSPACE_DIR via the
# ai-remote group - see docs/remote-workspace.md for the full mechanics,
# including the ACL-mask gotcha around locking individual secret files.
#
# It only sets the flag (and, if unset, the legacy account defaults) in
# config.env and then runs the normal prodstart - all the actual setup logic
# lives there.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Bitte mit sudo ausführen." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/claude-remote"
CONFIG_FILE="$CONFIG_DIR/config.env"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

set_config_var() {
    local key="$1"
    local value="$2"
    local escaped_val
    escaped_val=$(echo "$value" | sed 's/[\/&]/\\&/g')
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s/^${key}=.*/${key}=\"${escaped_val}\"/" "$CONFIG_FILE"
    else
        echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
    fi
}

set_config_var "DESKTOP_COMMANDER_ISOLATED_USER" "true"
grep -q "^DESKTOP_COMMANDER_USER=" "$CONFIG_FILE" || set_config_var "DESKTOP_COMMANDER_USER" "patigon-remote"
grep -q "^DESKTOP_COMMANDER_HOME=" "$CONFIG_FILE" || set_config_var "DESKTOP_COMMANDER_HOME" "/var/lib/patigon-remotemanagement"

echo "DESKTOP_COMMANDER_ISOLATED_USER=true gesetzt in $CONFIG_FILE."
echo "Starte prodstart im isolierten Legacy-Modus..."
echo ""

exec "$SCRIPT_DIR/prodstart.sh" "$@"
