# Claude Code background service

Runs Claude Code as an always-on service on macOS (LaunchAgent) and Linux (systemd user unit), with Remote Control, in a tmux session called `claude-service`.

## Install

```bash
./setup-claude-service.sh
```

Optional first-install values (they are only written to the config file once):

```bash
CLAUDE_MODE=server WORK_DIR=/opt/cicd GIT_REPO_URL= CLAUDE_NAME=beat ./setup-claude-service.sh
```

Sign in once with `claude`, then check `~/.claude/logs/daemon.log` and `tmux attach -t claude-service`.

## Config: `~/.claude/service.env`

Created on the first install and never overwritten. The watchdog re-reads it every minute, so changes apply without re-running the installer.

| Variable | Default | Meaning |
| --- | --- | --- |
| `CLAUDE_MODE` | `server` | `server` or `session`, see below. Changing it restarts the session. |
| `CLAUDE_NAME` | hostname | Name shown in claude.ai/code (server mode). |
| `WORK_DIR` | `$HOME` | Directory the session runs in. |
| `KEEP_AWAKE` | `yes` on macOS, `no` on Linux | `yes` blocks idle sleep while the session runs (`caffeinate -is` on macOS, `systemd-inhibit` on Linux). Changes apply the next time the session starts. |
| `GIT_REPO_URL` | empty | Repo kept as a read-only copy in `~/.claude-service-repo` (pulled hourly, fast-forward only, never executed). Private repo: SSH URL with a deploy key. |
| `CLAUDE_PERMISSION_MODE` | empty | Server mode only: `acceptEdits`, `auto`, `bypassPermissions`, `default`, `dontAsk`, `plan`. |

### Modes

- **`server`** (default): runs `claude remote-control --name <name> --continue`, falling back to a plain `claude remote-control`. The machine is listed as a computer in claude.ai/code and sessions are opened from there. `--continue` only reattaches to a session from the last ~4 hours.
- **`session`**: runs `claude --continue --remote-control`, falling back to `claude --remote-control`. One interactive session that always continues the last conversation in `WORK_DIR`, even an old or archived one. It is listed as a session, not as a computer.

## What the installer writes

- `~/.local/bin/claude-bootstrap.sh`: watchdog. Checks the session every minute and restarts it if missing, pulls the repo hourly, keeps `daemon.log` under 1 MB.
- `~/.claude/service.env`: the config above.
- `~/.claude/settings.json`: merged, not replaced. Adds basic allow rules and the SessionStart hook.
- `~/.claude/session_hook.default.sh`: rewritten on every run. Put your own output in `session_hook.user.sh` (created once).
- `~/.claude/on_start.txt`: if present, its text is sent once to the session, then renamed to `.processed`.
- Linux: `~/.config/systemd/user/claude.service` and linger via sudo (only if not already on). The older `claude-rc.service` is disabled if it exists. macOS: `~/Library/LaunchAgents/com.anthropic.claude.plist`.
