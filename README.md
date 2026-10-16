# Claude Code background service

Runs Claude Code as an always-on service on macOS (LaunchAgent) and Linux (systemd user unit). One Claude session lives in tmux (`claude-service`) with Remote Control, and continues the last conversation in `WORK_DIR`; it starts a new one only if there is none.

## Install

```bash
GIT_REPO_URL= WORK_DIR=$HOME ./setup-claude-service.sh
```

- `GIT_REPO_URL`: repo kept as a read-only copy in `~/.claude-service-repo` (fast-forward pull, hourly). Empty = no sync. A private repo needs an SSH URL with a deploy key or a URL with a read-only token.
- `WORK_DIR`: directory the session runs in (default `$HOME`).
- Sign in once with `claude`, then check `~/.claude/logs/daemon.log`.

## What it writes

- `~/.local/bin/claude-bootstrap.sh`: hourly watchdog (network check, repo pull, restarts the tmux session).
- `~/.claude/settings.json`: merged, not replaced. Adds basic allow rules and the SessionStart hook.
- `~/.claude/session_hook.default.sh`: rewritten on every run. Put your own output in `session_hook.user.sh` (created once).
- `~/.claude/on_start.txt`: if present, its text is sent once to the session, then renamed to `.processed`.
- Linux: `~/.config/systemd/user/claude.service` (enable-linger via sudo). macOS: `~/Library/LaunchAgents/com.anthropic.claude.plist`.

Repo content is never executed automatically.
