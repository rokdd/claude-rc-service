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
- **Inbox:** optional, other machines drop files into `~/inbox` over a write-only SSH key and the watchdog tells Claude about them (see [Inbox](#inbox-let-other-machines-drop-files)).
- **Forge mentions and assignments:** optional, a bot account that is assigned or mentioned on Forgejo/Gitea gets an inbox session for it (see [Forge mentions and assignments](#forge-mentions-and-assignments)).
- **Safe re-runs:** `settings.json` is merged, `service.env` and `session_hook.user.sh` are never overwritten, and an older `claude-rc.service` is disabled.

## Install

One command, straight from GitHub (copy and paste):

```bash
curl -fsSL https://raw.githubusercontent.com/rokdd/claude-rc-service/main/setup-claude-service.sh | bash
```

With your own first-install values (written to `service.env` once), put them before `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/rokdd/claude-rc-service/main/setup-claude-service.sh | CLAUDE_MODE=server WORK_DIR=/opt/cicd CLAUDE_NAME=beat bash
```

Afterwards open a new terminal (the installer adds `~/.local/bin` to `~/.zshrc`/`~/.bashrc`), sign in once with `claude`, and manage the service with `claude-service status|update|restart` (see Commands below).

From a clone of the repo:

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
| `CLAUDE_DEBUG` | `no` | `yes` keeps a debug log in `~/.claude/logs/rc-debug.log` (both modes). Turn it on to find out why Remote Control drops. Applies when the session next starts; a file over 20 MB is moved to `rc-debug.log.1` by the watchdog. In `server` mode the running session always logs to `rc-run.log` (needed for `SKIP_ARCHIVED`), which is appended to `rc-debug.log` when the next run starts. |
| `INBOX_WATCH` | `no` | `yes` makes the watchdog (once a minute) look in `INBOX_DIR` and, for each new or changed file, tell Claude in one line with the file names. `session` mode: the line is typed into the running conversation. `server` mode: a new Remote Control session named `inbox <host> <date time>` is started for the delivery (own tmux window, shows up in claude.ai/code). Its first prompt asks it to note the outcome in the Handover section of `~/.claude/CLAUDE.md`, mark the delivery done and then stop. It does not close itself (before 2.14.0 it did, which archived the session abruptly). If it needs a decision it asks in the session and waits for your answer. **The watchdog archives it when it is finished**: `INBOX_CLOSE_MINUTES` after all its deliveries are marked done and the window is quiet that long; a session that never finishes is closed after `INBOX_KEEP_HOURS` without activity. Only names matching `[A-Za-z0-9._-]` are announced, the contents are never typed into the session, and the line tells Claude to treat them as data from the sender. The first run only remembers the files already there. State: `~/.claude/state/inbox-seen`. **Status ledger** (2.11.0): every delivery is also written to `~/.claude/state/inbox-status` (`open`, `done`, `failed`). The inbox session marks it with `claude-service inbox done <file> "outcome"` before closing; if its window disappears without that, the watchdog marks it `failed`. The session hook prints open/failed items and the last 24 h of done items at session start, so other sessions on the machine see what is waiting or handled. `claude-service inbox [list\|all\|summary\|done ...]`. |
| `INBOX_TRUSTED` | `yes` | Deliveries in the inbox come from your own machines, so the inbox session treats them as approved and does what they ask without asking you first. It still asks (and waits) for steps that are destructive and cannot be undone, would expose a secret, break a rule in its instructions, or are unclear/unsafe. `no` = it asks whenever it needs a decision (the behaviour before 2.18.0). |
| `INBOX_CLOSE_MINUTES` | `10` | `server` mode: an inbox session whose deliveries are all marked done, and whose window had no output for this many minutes, is closed by the watchdog (its Remote Control session shows as archived). `0` = off. |
| `INBOX_KEEP_HOURS` | `24` | `server` mode: an inbox session window with no activity for this many hours is closed anyway (e.g. waiting for an answer that never came). `0` = never. |
| `INBOX_DIR` | `~/inbox` | Directory for `INBOX_WATCH`. Subfolders are relay outboxes (see [Hub of auto routing](#hub-of-auto-routing)). |
| `NET_FALLBACK_CMD` | `/usr/local/sbin/net-fallback` | When `api.anthropic.com` is unreachable the watchdog runs `<this> ensure` first. `net-fallback` (a small tool from host-autoupdate, any script with an `ensure` command works) then brings up a known Wi-Fi if the wired LAN has no internet, and turns it off again when the LAN is back. Needs passwordless `sudo` for that command (it re-runs itself with `sudo -n`). Empty or file missing = off. |
| `FORGE_URL` | empty | Forgejo/Gitea base URL, e.g. `https://git.example.com`. With `FORGE_TOKEN_FILE` set (and `INBOX_WATCH=yes`) the machine reacts to its bot account being assigned or mentioned, see [Forge mentions and assignments](#forge-mentions-and-assignments). Empty = off. |
| `FORGE_TOKEN_FILE` | empty | File (`chmod 600`) with the bot account's token. Scopes: `read:notification`, `write:notification`, `write:issue`. |
| `FORGE_USER` | empty | The bot's forge account name (what gets assigned/mentioned). Empty = asked from the API, which needs the extra token scope `read:user`. Set it. |
| `FORGE_ALLOWED_AUTHORS` | empty | Space separated forge users. Only issues or comments from them are delivered. Empty = everybody (fine only on a fully private forge: issue text is untrusted input). |
| `FORGE_POLL_SECONDS` | `120` | Seconds between polls. |
| `CLAUDE_TOKEN_FILE` | empty | Deprecated, ignored (setup-token tokens do not work for Remote Control, see below). |
| `SKIP_ARCHIVED` | `yes` | `server` mode: if you archived the session in claude.ai/code, Claude exits; the watchdog then starts it again **without** `--continue`, so the archived session is not reattached (and thereby un-archived). The machine stays listed with no session open. Detected from the run's own debug log `~/.claude/logs/rc-run.log` (emptied at every start; with `CLAUDE_DEBUG=yes` it is appended to `rc-debug.log`). `no` = always `--continue`. |

### Modes

- **`server`** (default): runs `claude remote-control --name <name> --continue`, falling back to a plain `claude remote-control`. The machine is listed as a computer in claude.ai/code and sessions are opened from there. `--continue` only reattaches to a session from the last ~4 hours.
- **`session`**: runs `claude --continue --remote-control`, falling back to `claude --remote-control`. One interactive session that always continues the last conversation in `WORK_DIR`, even an old or archived one. It is listed as a session, not as a computer.

### Reconnect and resume

1. systemd (`Restart=always`) or launchd (`KeepAlive`) starts the watchdog at boot and restarts it if it exits.
2. Every minute the watchdog checks that `api.anthropic.com` is reachable. Without a connection it waits and retries; nothing is restarted.
3. If the tmux session `claude-service` is gone (Claude crashed, was closed or the machine rebooted), it pre-answers the startup questions (only what is not yet set) and starts the session again there:
   - `session` mode: `claude --continue --remote-control` resumes the last conversation of `WORK_DIR`, however old. Only if there is none does it start a new one.
   - `server` mode: `claude remote-control --continue` reattaches to the last session if it is from the last ~4 hours; otherwise the machine comes back as a computer in claude.ai/code with no session open, and you start or pick one there. Exception: if the last run ended because you archived its session, it starts without `--continue`, so the session stays archived (`SKIP_ARCHIVED`).
4. Remote Control itself reconnects after short network drops while Claude keeps running, so the session stays the same.

### Machine not listed in claude.ai/code

The watchdog only checks that the tmux session exists, not that Remote Control is still registered. A process can keep running after network drops and still be missing from the list (seen once on a Raspberry Pi after several short "Reconnected" messages; the cause is not confirmed). To get the machine back and to find the cause:

1. Restart the session: `tmux kill-session -t claude-service`. The watchdog starts a new one within a minute and, in `server` mode, reattaches a session from the last ~4 hours.
2. Set `CLAUDE_DEBUG="yes"` in `~/.claude/service.env` and restart once. The next time the machine disappears, look at the end of `~/.claude/logs/rc-run.log` in `server` mode, `rc-debug.log` in `session` mode (and `tmux capture-pane -pt claude-service -S -200`) for the last connection or registration error before restarting.
3. Check `~/.claude/logs/daemon.log` for "No connection to api.anthropic.com" around that time. Short gaps there are normal on Wi-Fi.
4. If the machine is on Wi-Fi, switching to a cable or turning off Wi-Fi power saving (`iw dev wlan0 set power_save off`) removes most drops.

Conversations are stored per directory in `~/.claude/projects/`, so keep `WORK_DIR` fixed if you want to resume. Anything a resumed or new session must know can go into `~/.claude/CLAUDE.md` or the user hook below.

## Long-lived token: does not work

Tokens from `claude setup-token` are inference-only. With one set as `CLAUDE_CODE_OAUTH_TOKEN`, `claude remote-control` exits about half a second after each start (tested on ubiter, 2026-11-02; the error text blames the network), so the machine drops out of claude.ai/code. `CLAUDE_TOKEN_FILE` (2.8.0) is therefore ignored since 2.10.0: the watchdog logs a line and uses the `/login` session. If you set it on an older install, empty it in `service.env` and restart.

The `/login` session runs out after about 30 days (Linux: renew in `tmux attach -t claude-service`, `/login`). Watch for it with a timer that checks `claude auth status`.

## Inbox: let other machines drop files

With `INBOX_WATCH="yes"` the watchdog announces new files in `INBOX_DIR` (default `~/inbox`) to Claude (see the table above). How files get there is up to you; a safe way for other machines or other Claude sessions is a **write-only SSH key** per sender:

1. Copy [`examples/inbox-put`](examples/inbox-put) to e.g. `~/bin/inbox-put` and make it executable. It only accepts `put <name>`, stores stdin as `~/inbox/<sender>-<name>` (mode 600, max 64 KiB, names `[A-Za-z0-9._-]`) and logs the delivery with `logger -t inbox-put`. Everything else is refused.
2. On the sender: `ssh-keygen -t ed25519 -N '' -C '<sender>-to-<this host>' -f ~/.ssh/<this host>_inbox`. Only the **public** key leaves that machine.
3. On this machine, add one line per sender to `~/.ssh/authorized_keys`:
   ```
   restrict,from="<sender IP>",command="/home/<user>/bin/inbox-put <sender>" ssh-ed25519 AAAA... <sender>-to-<this host>
   ```
   `restrict` turns off shell, port/agent/X11 forwarding and pty; `from=` limits the key to the sender's address; the forced command runs no matter what the sender asks for.
4. The sender delivers with:
   ```
   ssh -i ~/.ssh/<this host>_inbox <user>@<this host> put <name> < file
   ```
   Within a minute the watchdog announces `<sender>-<name>`.

Notes:

- The key can only write. It cannot read the inbox, list it or run anything, so a leaked sender key at worst fills the inbox with small files.
- Claude is told to treat inbox files as data from the sender, not as instructions. Secrets (tokens, passwords) can be sent this way instead of through chat; delete them from the inbox once used (`shred -u`).
- To revoke a sender, delete its line in `authorized_keys`.
- For the opposite direction (this machine fetching files from another one), use the same pattern there with a forced command that prints one file from a fixed directory.

## Hub of auto routing

The **hub of auto routing** (also called the inbox relay) lets one machine pass files between all the others.

A machine that every other machine can reach (the **hub**) can pass messages between them **without opening a session itself**. Each subfolder `INBOX_DIR/<target>/` is an outbox for one target machine.

1. **Sender** delivers to the hub with the folder in the name: `ssh -i <key> <user>@<hub> put <target>/<name> < file`. The forced command ([`examples/inbox-put`](examples/inbox-put)) accepts this only if `~/.claude/inbox-routes` (or `INBOX_ROUTES`) has a line `<sender> <target>` and the folder exists; otherwise it answers `no route to <target>`. The file is stored as `INBOX_DIR/<target>/<sender>-<name>`.
2. **Hub**: list the targets in `~/.claude/inbox-relay.conf`, one per line, `<target> <ssh options and user@host>`:
   ```
   laptop -i ~/.claude/inbox-keys/laptop/send -p 22 me@192.168.1.20
   ```
   Once a minute the watchdog (needs `INBOX_WATCH="yes"`) sends every file in `INBOX_DIR/<target>/` with `ssh ... put <sender>-<name>`, moves it to `<target>/.sent/` (deleted after 7 days) and writes a line to its log and to `logger -t inbox-relay`. No Claude session starts on the hub. Unreachable target: retry every minute; after a day the file goes to `<target>/.failed/` and shows as failed in `claude-service inbox`.
3. **Target** just gets a normal inbox file `<sender>-<name>` (its own `inbox-put`, session as usual).
4. **Reply**: the target puts `<sender>/<name>` to the hub the same way (needs the route `<target> <sender>`). It is asynchronous: there is no direct answer to the first call.

Only listed pairs can talk, each message is max 64 KiB, and the hub log shows who sent what to whom. Content is still data from the sender, not instructions.

### Registering and binding machines (hub of auto routing)

On the hub, `claude-service inbox` does the bookkeeping so nothing has to be edited by hand:

| Command | What it does |
|---|---|
| `inbox register <name> --host <user@address> [--port N] [--from <ip>]` | Creates the outbox folder, two key pairs (hub to machine, machine to hub), the restricted key line for the machine (`from=` its address) and the line in `inbox-relay.conf`, and writes a **setup bundle** `~/.claude/inbox-bundle-<name>.sh`. The machine can talk to nobody yet. |
| `inbox bind <from> <to> [--both]` / `unbind` | Allows (removes) the route `<from>` -> `<to>`. Both must exist (a key `<from>-to-<hub>`, a folder `<to>`). |
| `inbox machines [--check]` | Lists targets (waiting/failed files; `--check` tests the ssh login), senders and routes. |
| `inbox remove <name> [-y]` | Removes keys, routes, relay line and the folder (kept if files are in it). |

The bundle holds the machine's **private** key. It is never printed: copy it to the machine by hand, run it once there (installs `~/bin/inbox-put`, adds the hub's key to `~/.ssh/authorized_keys`, stores the key for sending to the hub, prints the send and test commands) and `shred -u` it on both sides. The new machine's own inbox only opens sessions if it runs this service with `INBOX_WATCH="yes"`. Setting `INBOX_HUB` (`user@address[:port]`), `INBOX_HUB_NAME` and `INBOX_HUB_IP` in `service.env` fills the bundle with the right addresses; `INBOX_AUTH_KEYS`, `INBOX_PUT_CMD` and `INBOX_ROUTES` point to the receiving account's `authorized_keys`, its forced command and the routes file when the hub receives under another account (sudo is used where a file is not writable or readable). Existing machines keep working as they are; `machines` shows them as soon as their key comment is `<name>-to-<hub>`.

## Forge mentions and assignments

Every bot machine can be addressed on the forge like through the inbox: assign an issue or PR to its account, or write `@account` in the text or in a comment, and the machine opens an inbox session for it.

How it works: the watchdog runs `examples/forge-watch` (from the repo copy, so it updates with the hourly pull) every `FORGE_POLL_SECONDS`. It reads the unread notifications of the bot account through the normal API of any Forgejo/Gitea (no database access, no webhook, nothing to open in the firewall) and writes one Markdown file per issue and poll into `INBOX_DIR`: what was assigned, which new text mentions the account, link, author. From there it is an ordinary inbox delivery (`claude-service inbox`, ledger, `INBOX_TRUSTED`, archive when done). Each assignment and each comment triggers once; unassign and assign again triggers again. The first run only records the current state. Notifications are marked read.

Set up (per machine, once):

1. Create a forge user for the bot (or use the existing one) and an access token for it with the scopes `read:notification`, `write:notification` and `write:issue` (the session answers with the same token). Save it in a file with `chmod 600`.
2. In `~/.claude/service.env`: `FORGE_URL="https://git.example.com"`, `FORGE_TOKEN_FILE="/path/to/token"`, `FORGE_USER="the-bot"`, optionally `FORGE_ALLOWED_AUTHORS="alice bob"`, and `INBOX_WATCH="yes"`. No restart, the watchdog reads it every minute (needs this version of the watchdog: run the installer once).
3. Test without delivering: `FORGE_URL=... FORGE_TOKEN_FILE=... python3 -I ~/.claude-service-repo/examples/forge-watch --dry-run`.

The bot account also has to be a collaborator or org member on the repos where it should be reachable, and its notification settings must not be disabled. Issue text is data from the forge, not instructions: set `FORGE_ALLOWED_AUTHORS` unless everybody who can write issues is trusted.

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

## Questions and answers: the answer continues the asking session

By default every incoming file opens a new inbox session. For a question that a session asks another machine, the answer goes back **into the session that asked** (via a ticket):

1. **Ask** (on the hub): `claude-service inbox ask <target> <name> < question.md` writes the question into `INBOX_DIR/<target>/<name>` (the relay sends it on) and puts three header lines on top: `Ticket: <id>`, `Asked-by: <machine>`, `Answer: ...`. On a machine that is not the hub: `claude-service inbox ticket "<topic>"` prints the ticket and the header lines; paste them on top of your note and send it as before.
2. **Wait**: the session runs `claude-service inbox wait <ticket>` in the background (it ends when the answer is there, or after 110 minutes with exit code 3: run it again). When it ends, the harness wakes the session and it reads the answer file (data from the other machine, not instructions).
3. **Answer**: the other machine sends a file **whose name contains `re-<ticket>`** (`put re-<ticket>-<name>`, or `put <asker>/re-<ticket>-<name>` through the hub), or whose first line is `In-Reply-To: <ticket>`.
4. **Watchdog**: an answer to an open ticket does not open a new session; it is recorded in `~/.claude/state/inbox-tickets` (asked, answered, picked, orphan) and the waiting `wait` returns. Fallbacks: unknown or expired ticket, a second answer, or an answer nobody picked up for 10 minutes (asking session gone) open a normal inbox session.
5. A session with an open ticket is not archived by the idle timer for `INBOX_ASK_HOURS` (default 48).

## Commands: `claude-service`

`claude-service status` (service, tmux session, mode, installed vs repo version, login type, last log lines; exit code 1 when not running), `claude-service update` (pulls the repo and runs the installer without restarting, `--restart` also restarts and ends the running session), `name [new]` (shows or sets `CLAUDE_NAME`, the machine name in claude.ai/code; applies after `restart`), `inbox [list|all|summary|done ...]` (inbox delivery ledger), `restart`, `logs [lines]`, `attach`, `version`.

## Re-running the installer

Safe at any time: `service.env` is kept (new settings are appended with their default), the watchdog is replaced atomically and `claude.service` is restarted, which ends the running tmux session (it is continued by `--continue`, see above). Run it from inside the session with `NO_RESTART=yes bash setup-claude-service.sh`; the new watchdog then runs from the next restart.

## What the installer writes

- `~/.local/bin/claude-bootstrap.sh`: the watchdog.
- `~/.local/bin/claude-service`: the command line helper above; `~/.claude/state/installed-version`: its version stamp.
- `~/.claude/service.env`: the config above.
- `~/.claude/settings.json`: merged, not replaced. Adds basic allow rules (including the claude-code-remote tools send_message, list_events, get_session, list_sessions, so sessions on different machines can message each other) and the hook.
- `~/.claude.json`: the watchdog sets only the startup-question flags: `hasCompletedOnboarding`, `remoteDialogSeen`, `bypassPermissionsModeAccepted` (bypassPermissions mode only), and for `WORK_DIR` (also after you change it) `hasTrustDialogAccepted` and the CLAUDE.md includes flags. Nothing else. Signing in (`claude` once) is still manual.
- `~/.claude/inbox-relay.conf`, `~/.claude/inbox-routes`: relay targets (watchdog) and allowed sender/target pairs (forced command).
- `~/.claude/state/inbox-seen`: written by the watchdog when `INBOX_WATCH=yes`.
- `~/.claude/on_start.txt`: if present, its text is sent once to the session, then renamed to `.processed`.
- Linux: `~/.config/systemd/user/claude.service`, plus linger via sudo (only if not already on).
- macOS: `~/Library/LaunchAgents/com.anthropic.claude.plist`.

## License and mirror

GPL-3.0, see `LICENSE`. The repo is https://github.com/rokdd/claude-rc-service, which is the URL installs pull from (reachable everywhere, no login).
