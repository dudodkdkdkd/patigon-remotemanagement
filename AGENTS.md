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

- Claude Code and Codex currently run as `root`. Desktop Commander's default (`DESKTOP_COMMANDER_ISOLATED_USER=false`) runs it as whoever ran `sudo prodstart` (`$SUDO_USER`), with that user's real home — full access to everything that user can see, by design, not a bug. The old isolated `patigon-remote` service account + curated ACL workspace is now opt-in only, via `scripts/prodstart-isolated-desktop-commander.sh` / `DESKTOP_COMMANDER_ISOLATED_USER=true`.
- `WORKSPACE_DIR` defines the intended project access. Never apply recursive ownership or permission changes to a user's home, `secret`, `.ssh`, or system directories — this still applies in the isolated legacy mode; the dynamic default mode intentionally has no such boundary.
- The bind-mount/symlink-farm/ACL workspace curation described in `docs/remote-workspace.md` only applies when `DESKTOP_COMMANDER_ISOLATED_USER=true`. Check the actual VPS state (`grep DESKTOP_COMMANDER_ISOLATED_USER /etc/claude-remote/config.env`, `systemctl cat desktop-commander-remote`) before assuming either mode is live — the doc's "verified" table can be stale.
- Pairing must use the same service user and home as the systemd unit. A running service alone does not prove remote execution works; verify a real `hostname`, `whoami`, `pwd`, and workspace listing through ChatGPT.
- Before deploying, inspect the VPS checkout and service status, then record the commit being deployed. Preserve a path back to the prior commit for rollback.
