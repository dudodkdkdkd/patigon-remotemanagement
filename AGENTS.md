# AGENTS.md

Codex reads this file as project guidance for `patigon-remotemanagement`.

## Working rules

- State assumptions before changing production behavior. Ask when the target VPS, workspace scope, or requested service selection is unclear.
- Make the smallest change that solves the request. Keep the existing Bash structure and avoid unrelated refactors.
- For multi-step work, use short checkpoints with a way to verify each one.
- Check shell syntax and run the relevant tests before claiming a change works.
- Do not print or commit values from `config.env`, `.env`, device credentials, SSH keys, or the `secret` directory.

## Repository

- `scripts/prodstart.sh` installs and starts the selected Linux systemd services.
- `scripts/prodstop.sh` stops services; a normal stop preserves Desktop Commander device credentials.
- `scripts/devstart.sh` runs enabled services locally as the current non-root user.
- `config.env.example` documents the production and local settings. Keep its defaults consistent with the scripts.
- Shell tests live in `tests/` and run with `bash tests/<name>.sh`.

## Production boundaries

- Claude Code and Codex currently run as `root`. Desktop Commander runs as the dedicated `patigon-remote` user.
- `WORKSPACE_DIR` defines the intended project access. Never apply recursive ownership or permission changes to a user's home, `secret`, `.ssh`, or system directories.
- Pairing must use the same service user and home as the systemd unit. A running service alone does not prove remote execution works; verify a real `hostname`, `whoami`, `pwd`, and workspace listing through ChatGPT.
- Before deploying, inspect the VPS checkout and service status, then record the commit being deployed. Preserve a path back to the prior commit for rollback.
