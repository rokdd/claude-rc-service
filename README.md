# Claude Code background service

Runs Claude Code as an always-on service on macOS (LaunchAgent) and Linux (systemd user unit), with Remote Control, in a tmux session called `claude-service`.

## Features

- **Two modes:** `server` lists the machine as a computer in claude.ai/code. `session` keeps one interactive conversation that always continues.
- **Reconnect and resume:** after a crash, reboot or network loss the watchdog starts the session again and continues the last conversation (see [Reconnect and resume](#reconnect-and-resume)).
- **Watchdog:** checks the session every minute and restarts it if it died. Needs a connection to `api.anthropic.com`.
- **Config file:** `~/.claude/service.env`, re-read every minute, no re-install needed.
- **Session hook:** every session start prints host information into Claude's context, plus your own lines (see below).
- **One-shot prompt:** put text in `~/.claude/on_start.txt` and the running session receives it once.
- **Repo sync:** optional read-only copy of a Git repo, pulled hourly. Nothing from it is executed.
- **Keep awake:** optional, blocks idle sleep while the session runs.
- **Safe re-runs:** `settings.json` is merged, `service.env` and `session_hook.user.sh` are never overwritten, and an older `claude-rc.service` is disabled.

## Install

Plain install with the defaults:

```bash
./setup-claude-service.sh
```

With your own first-install values (written to `service.env` once; to change them later, edit that file):

```bash
CLAUDE_MODE=server \
WORK_DIR=/opt/cicd \
CLAUDE_NAME=beat \
KEEP_AWAKE=no \
GIT_REPO_URL=https://github.com/rokdd/claude-rc-service.git \
./setup-claude-service.sh
```

Set `GIT_REPO_URL=` (empty) to turn repo sync off. Then sign in once with `claude`. Logs: `~/.claude/logs/daemon.log`. Attach: `tmux attach -t claude-service`.

## Config: `~/.claude/service.env`

Created on the first install and never overwritten. The watchdog re-reads it every minute. The default repo URL is the `GIT_REPO_URL` line at the top of `setup-claude-service.sh`; change that one line when the repo moves.

| Variable | Default | Meaning |
| --- | --- | --- |
| `CLAUDE_MODE` | `server` | `server` or `session`, see below. Changing it restarts the session. |
| `CLAUDE_NAME` | hostname | Name shown in claude.ai/code (server mode). |
| `WORK_DIR` | `$HOME` | Directory the session runs in. |
| `KEEP_AWAKE` | `yes` on macOS, `no` on Linux | `yes` blocks idle sleep (`caffeinate -is` on macOS, `systemd-inhibit` on Linux). Applies when the session next starts. |
| `GIT_REPO_URL` | the repo's URL | Read-only copy in `~/.claude-service-repo`, pulled hourly (fast-forward only). Empty = off. The default repo is public, so no login is needed; a private repo needs an SSH URL with a deploy key. |
| `CLAUDE_PERMISSION_MODE` | empty | Server mode only: `acceptEdits`, `auto`, `bypassPermissions`, `default`, `dontAsk`, `plan`. |

### Modes

- **`server`** (default): runs `claude remote-control --name <name> --continue`, falling back to a plain `claude remote-control`. The machine is listed as a computer in claude.ai/code and sessions are opened from there. `--continue` only reattaches to a session from the last ~4 hours.
- **`session`**: runs `claude --continue --remote-control`, falling back to `claude --remote-control`. One interactive session that always continues the last conversation in `WORK_DIR`, even an old or archived one. It is listed as a session, not as a computer.

### Reconnect and resume

1. systemd (`Restart=always`) or launchd (`KeepAlive`) starts the watchdog at boot and restarts it if it exits.
2. Every minute the watchdog checks that `api.anthropic.com` is reachable. Without a connection it waits and retries; nothing is restarted.
3. If the tmux session `claude-service` is gone (Claude crashed, was closed or the machine rebooted), it starts it again in `WORK_DIR`:
   - `session` mode: `claude --continue --remote-control` resumes the last conversation of `WORK_DIR`, however old. Only if there is none does it start a new one.
   - `server` mode: `claude remote-control --continue` reattaches to the last session if it is from the last ~4 hours; otherwise the machine comes back as a computer in claude.ai/code with no session open, and you start or pick one there.
4. Remote Control itself reconnects after short network drops while Claude keeps running, so the session stays the same.

Conversations are stored per directory in `~/.claude/projects/`, so keep `WORK_DIR` fixed if you want to resume. Anything a resumed or new session must know can go into `~/.claude/CLAUDE.md` or the user hook below.

## Session hook

The installer adds a `SessionStart` hook to `~/.claude/settings.json` that runs `~/.claude/session_hook.default.sh`. Whatever the hook prints becomes part of Claude's context when a session starts or resumes.

- `session_hook.default.sh`: rewritten on every install. Prints the wrapper version, host name, user and time, then runs your hook and shows `~/.claude/local_artifact.txt` if it exists.
- `session_hook.user.sh`: created once, yours to edit. Example: print `hostname`, the number of CPU cores or a note like "this machine is the build server".
- `local_artifact.txt`: free text about this machine, shown at every session start.

Examples for `session_hook.user.sh` are in [`examples/user-session-hooks/`](examples/user-session-hooks/). Copy the lines you want into your own hook; nothing there runs by itself.

- `handover.sh` + `CLAUDE.md.example`: reminds Claude to keep handover notes in `~/.claude/CLAUDE.md`, so another session can take over at any time.
- `machine-info.sh`: prints OS, cores and free disk space.

## What the installer writes

- `~/.local/bin/claude-bootstrap.sh`: the watchdog.
- `~/.claude/service.env`: the config above.
- `~/.claude/settings.json`: merged, not replaced. Adds basic allow rules and the hook.
- `~/.claude/on_start.txt`: if present, its text is sent once to the session, then renamed to `.processed`.
- Linux: `~/.config/systemd/user/claude.service`, plus linger via sudo (only if not already on).
- macOS: `~/Library/LaunchAgents/com.anthropic.claude.plist`.
