#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
launcher_pid=""
cleanup() {
    if [ -n "$launcher_pid" ]; then
        kill -TERM "$launcher_pid" 2>/dev/null || true
        wait "$launcher_pid" 2>/dev/null || true
    fi
    rm -rf "$test_dir"
}
trap cleanup EXIT

if [ "$EUID" -eq 0 ]; then
    echo "SKIP: devstart muss als normaler Benutzer getestet werden."
    exit 0
fi

cat > "$test_dir/fake-desktop-commander" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$$" "$1" > "$FAKE_ARGS_FILE"
exec sleep 30
EOF
chmod +x "$test_dir/fake-desktop-commander"

cat > "$test_dir/.env" <<EOF
RUN_CLAUDE=false
RUN_CODEX=false
RUN_DESKTOP_COMMANDER=true
DESKTOP_COMMANDER_PATH=$test_dir/fake-desktop-commander
WORKSPACE_DIR=$test_dir/workspace
EOF

export FAKE_ARGS_FILE="$test_dir/args"
original_dir="$PWD"
cd "$test_dir"
bash "$repo_dir/scripts/devstart.sh" > "$test_dir/output" 2>&1 &
launcher_pid="$!"
cd "$original_dir"

for _ in {1..50}; do
    [ -s "$FAKE_ARGS_FILE" ] && break
    sleep 0.1
done
[ -s "$FAKE_ARGS_FILE" ] || { cat "$test_dir/output"; exit 1; }
read -r child_pid command_arg < "$FAKE_ARGS_FILE"
[ "$command_arg" = remote ] || { echo "Falsches CLI-Argument: $command_arg"; exit 1; }

kill -TERM "$launcher_pid"
wait "$launcher_pid" || true
launcher_pid=""
if kill -0 "$child_pid" 2>/dev/null; then
    echo "Desktop Commander wurde bei SIGTERM nicht beendet."
    exit 1
fi
rg -q 'Desktop Commander gestoppt' "$test_dir/output"

cat > "$test_dir/fake-service" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$$" "$1" >> "$FAKE_ALL_FILE"
exec sleep 30
EOF
chmod +x "$test_dir/fake-service"
mkdir -p "$test_dir/home/.claude" "$test_dir/home/.codex"
touch "$test_dir/home/.claude/.credentials.json" "$test_dir/home/.codex/auth.json"
cat > "$test_dir/.env" <<EOF
RUN_CLAUDE=true
RUN_CODEX=true
RUN_DESKTOP_COMMANDER=true
CLAUDE_PATH=$test_dir/fake-service
CODEX_PATH=$test_dir/fake-service
DESKTOP_COMMANDER_PATH=$test_dir/fake-service
WORKSPACE_DIR=$test_dir/workspace
EOF
export FAKE_ALL_FILE="$test_dir/all-args"
cd "$test_dir"
HOME="$test_dir/home" bash "$repo_dir/scripts/devstart.sh" > "$test_dir/all-output" 2>&1 &
launcher_pid="$!"
cd "$original_dir"

for _ in {1..50}; do
    [ -f "$FAKE_ALL_FILE" ] && [ "$(wc -l < "$FAKE_ALL_FILE")" -eq 3 ] && break
    sleep 0.1
done
[ -f "$FAKE_ALL_FILE" ] && [ "$(wc -l < "$FAKE_ALL_FILE")" -eq 3 ] || { cat "$test_dir/all-output"; exit 1; }
[ "$(rg -c '^.* remote-control$' "$FAKE_ALL_FILE")" -eq 2 ]
[ "$(rg -c '^.* remote$' "$FAKE_ALL_FILE")" -eq 1 ]
kill -TERM "$launcher_pid"
wait "$launcher_pid" || true
launcher_pid=""
while read -r child_pid _; do
    if kill -0 "$child_pid" 2>/dev/null; then
        echo "Dienst mit PID $child_pid wurde nicht beendet."
        exit 1
    fi
done < "$FAKE_ALL_FILE"
for name in Claude Codex 'Desktop Commander'; do
    rg -q "$name gestoppt" "$test_dir/all-output"
done

cat > "$test_dir/.env" <<EOF
RUN_CLAUDE=false
RUN_CODEX=false
RUN_DESKTOP_COMMANDER=false
WORKSPACE_DIR=$test_dir/workspace
EOF
if (cd "$test_dir" && bash "$repo_dir/scripts/devstart.sh") > "$test_dir/disabled-output" 2>&1; then
    echo "devstart hätte ohne aktivierten Dienst abbrechen müssen."
    exit 1
fi

echo "PASS: Desktop Commander startet einzeln und mit Claude/Codex; Cleanup und deaktivierte Konfiguration geprüft."
