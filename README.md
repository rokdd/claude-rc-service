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
- **No permission questions:** sessions run with `--permission-mode bypassPermissions` by default, so Claude never stops to ask before a command or file change. Only use this on machines where Claude may do anything the user can. Set `CLAUDE_PERMISSION_MODE=` (empty) to get the questions back.
- **No startup questions:** before the session starts, the watchdog pre-answers Claude's one-time questions in `~/.claude.json` (onboarding, Remote Control intro, "Do you trust the files in this folder?" for `WORK_DIR`, CLAUDE.md external includes, and the bypassPermissions warning when that mode is set: `bypassPermissionsModeAccepted` in `~/.claude.json` and `skipDangerousModePermissionPrompt` in `~/.claude/settings.json`, which Claude Code 2.1 reads), so a start with nobody attached never hangs. Installing means you trust `WORK_DIR`.
- **Safe re-runs:** `settings.json` is merged, `service.env` and `session_hook.user.sh` are never overwritten, and an older `claude-rc.service` is disabled.

## Install

Plain install with the defaults:

```bash
./setup-claude-service.sh
```

If your copy lost the executable bit (zip download, some file systems), run `bash setup-claude-service.sh` instead; it takes the same variables.

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
| `GIT_REPO_URL` | the repo's URL | Read-only copy in `~/.claude-service-repo`, pulled hourly (fast-forward only). Empty = off. Changing it moves the existing copy to the new URL at the next sync (needs the same history, e.g. a mirror). The default repo is public, so no login is needed; a private repo needs an SSH URL with a deploy key. |
| `CLAUDE_PERMISSION_MODE` | `bypassPermissions` | Both modes. Default allows everything without asking (any command, any file). Other values: `acceptEdits`, `auto`, `default`, `dontAsk`, `plan`. Empty = Claude's normal questions. Applies when the session next starts. |
| `CLAUDE_DEBUG` | `no` | `yes` makes Claude write a debug log to `~/.claude/logs/rc-debug.log` (both modes). Turn it on to find out why Remote Control drops. Applies when the session next starts; a file over 20 MB is moved to `rc-debug.log.1` by the watchdog. |
| `INBOX_WATCH` | `no` | `yes` makes the watchdog (once a minute) look in `INBOX_DIR` and, for each new or changed file, tell Claude in one line with the file names. `session` mode: the line is typed into the running conversation. `server` mode: a new Remote Control session named `inbox <host> <date time>` is started for the delivery (own tmux window, shows up in claude.ai/code). Only names matching `[A-Za-z0-9._-]` are announced, the contents are never typed into the session, and the line tells Claude to treat them as data from the sender. The first run only remembers the files already there. State: `~/.claude/state/inbox-seen`. |
| `INBOX_DIR` | `~/inbox` | Directory for `INBOX_WATCH`. |

### Modes

- **`server`** (default): runs `claude remote-control --name <name> --continue`, falling back to a plain `claude remote-control`. The machine is listed as a computer in claude.ai/code and sessions are opened from there. `--continue` only reattaches to a session from the last ~4 hours.
- **`session`**: runs `claude --continue --remote-control`, falling back to `claude --remote-control`. One interactive session that always continues the last conversation in `WORK_DIR`, even an old or archived one. It is listed as a session, not as a computer.

### Reconnect and resume

1. systemd (`Restart=always`) or launchd (`KeepAlive`) starts the watchdog at boot and restarts it if it exits.
2. Every minute the watchdog checks that `api.anthropic.com` is reachable. Without a connection it waits and retries; nothing is restarted.
3. If the tmux session `claude-service` is gone (Claude crashed, was closed or the machine rebooted), it pre-answers the startup questions (only what is not yet set) and starts the session again there:
   - `session` mode: `claude --continue --remote-control` resumes the last conversation of `WORK_DIR`, however old. Only if there is none does it start a new one.
   - `server` mode: `claude remote-control --continue` reattaches to the last session if it is from the last ~4 hours; otherwise the machine comes back as a computer in claude.ai/code with no session open, and you start or pick one there.
4. Remote Control itself reconnects after short network drops while Claude keeps running, so the session stays the same.

### Machine not listed in claude.ai/code

The watchdog only checks that the tmux session exists, not that Remote Control is still registered. A process can keep running after network drops and still be missing from the list (seen once on a Raspberry Pi after several short "Reconnected" messages; the cause is not confirmed). To get the machine back and to find the cause:

1. Restart the session: `tmux kill-session -t claude-service`. The watchdog starts a new one within a minute and, in `server` mode, reattaches a session from the last ~4 hours.
2. Set `CLAUDE_DEBUG="yes"` in `~/.claude/service.env` and restart once. The next time the machine disappears, look at the end of `~/.claude/logs/rc-debug.log` (and `tmux capture-pane -pt claude-service -S -200`) for the last connection or registration error before restarting.
3. Check `~/.claude/logs/daemon.log` for "No connection to api.anthropic.com" around that time. Short gaps there are normal on Wi-Fi.
4. If the machine is on Wi-Fi, switching to a cable or turning off Wi-Fi power saving (`iw dev wlan0 set power_save off`) removes most drops.

Conversations are stored per directory in `~/.claude/projects/`, so keep `WORK_DIR` fixed if you want to resume. Anything a resumed or new session must know can go into `~/.claude/CLAUDE.md` or the user hook below.

## Session hook

The installer adds a `SessionStart` hook to `~/.claude/settings.json` that runs `~/.claude/session_hook.default.sh`. Whatever the hook prints becomes part of Claude's context when a session starts or resumes.

- `session_hook.default.sh`: rewritten on every install. Prints the wrapper version, host name, user and time, then runs your hook and shows `~/.claude/local_artifact.txt` if it exists.
- `session_hook.user.sh`: created once, yours to edit. Example: print `hostname`, the number of CPU cores or a note like "this machine is the build server".
- `local_artifact.txt`: free text about this machine, shown at every session start.

### Example user hook

[`examples/session_hook.user.sh`](examples/session_hook.user.sh) is a ready-to-use user hook. Copy it as-is:

```bash
cp examples/session_hook.user.sh ~/.claude/session_hook.user.sh
```

Settings at the top of the file (`yes`/`no`; they can also be set in `service.env`):

| Setting | Default | What it does |
| --- | --- | --- |
| `HANDOVER` | `yes` | Claude keeps a Handover section in `~/.claude/CLAUDE.md` current (state, open tasks, where things live), so another session can take over at any time. Longer write-ups go into Claude artifacts, linked there and read only when needed. |
| `TOPICS` | `yes` | Special subjects (a script, a service, a project) get their own file `~/.claude/topics/<topic>.md` (first line `# <title>`), so `CLAUDE.md` stays short. At start the hook lists them and Claude offers to load one. |
| `MACHINE_INFO` | `yes` | Prints OS, cores and free disk space. |
| `TELL_USER` | `yes` | Claude says once, in its first reply, which features are on and how to opt out. |

## Re-running the installer

Safe at any time: `service.env` is kept (new settings are appended with their default), the watchdog is replaced atomically and `claude.service` is restarted, which ends the running tmux session (it is continued by `--continue`, see above). Run it from inside the session with `NO_RESTART=yes bash setup-claude-service.sh`; the new watchdog then runs from the next restart.

## What the installer writes

- `~/.local/bin/claude-bootstrap.sh`: the watchdog.
- `~/.claude/service.env`: the config above.
- `~/.claude/settings.json`: merged, not replaced. Adds basic allow rules (including the claude-code-remote tools send_message, list_events, get_session, list_sessions, so sessions on different machines can message each other) and the hook.
- `~/.claude.json`: the watchdog sets only the startup-question flags: `hasCompletedOnboarding`, `remoteDialogSeen`, `bypassPermissionsModeAccepted` (bypassPermissions mode only), and for `WORK_DIR` (also after you change it) `hasTrustDialogAccepted` and the CLAUDE.md includes flags. Nothing else. Signing in (`claude` once) is still manual.
- `~/.claude/state/inbox-seen`: written by the watchdog when `INBOX_WATCH=yes`.
- `~/.claude/on_start.txt`: if present, its text is sent once to the session, then renamed to `.processed`.
- Linux: `~/.config/systemd/user/claude.service`, plus linger via sudo (only if not already on).
- macOS: `~/Library/LaunchAgents/com.anthropic.claude.plist`.

## License and mirror

GPL-3.0, see `LICENSE`. The repo is https://github.com/rokdd/claude-rc-service, which is the URL installs pull from (reachable everywhere, no login).
