#!/bin/bash
# Installs Claude Code as an always-on background service (macOS LaunchAgent / Linux systemd user unit).
# It keeps one Claude session alive in tmux with Remote Control, continuing the last conversation.
set -e

# === FIRST-INSTALL DEFAULTS (override with environment variables) ===
# They are written once to ~/.claude/service.env; edit that file afterwards, the watchdog re-reads it every minute.
SCRIPT_VERSION="2.1.0"
# Repo with shared hooks/tasks: the only place that names it. Change this line when the repo moves (e.g. to GitHub).
# Private repo: use an SSH URL with a deploy key, or a URL with a read-only token. Empty = no syncing.
GIT_REPO_URL="${GIT_REPO_URL-https://github.com/rokdd/claude-rc-service.git}"
# Directory the session runs in (its conversations are continued per directory).
WORK_DIR="${WORK_DIR:-$HOME}"
CLAUDE_MODE="${CLAUDE_MODE:-server}"   # server = machine shows up as a computer in claude.ai/code; session = one continued interactive session
CLAUDE_NAME="${CLAUDE_NAME:-$(hostname -s)}"
CLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE-bypassPermissions}"   # allow everything without asking; empty = Claude's normal questions
if [[ "$OSTYPE" == "darwin"* ]]; then KEEP_AWAKE="${KEEP_AWAKE:-yes}"; else KEEP_AWAKE="${KEEP_AWAKE:-no}"; fi   # yes = block idle sleep while the session runs
TARGET_DIR="$HOME/.claude"
REPO_DIR="$HOME/.claude-service-repo"
# ===========================================================

echo "Starting deployment (version $SCRIPT_VERSION)..."

# 1. OS detection and prerequisites
mkdir -p "$HOME/.local/bin" "$TARGET_DIR/logs"
export PATH="$HOME/.local/bin:$PATH"

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
    command -v tmux >/dev/null || { echo "tmux is missing. Install it first (brew install tmux)."; exit 1; }
else
    OS="linux"
    missing=""
    for c in curl git tmux; do command -v "$c" >/dev/null || missing="$missing $c"; done
    if [ -n "$missing" ]; then
        echo "Installing:$missing"
        sudo apt-get update && sudo apt-get install -y $missing
    fi
fi

# 2. Claude Code
if ! command -v claude >/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# 3. Hooks (default hook is rewritten on every run, the user hook is created once)
cat > "$TARGET_DIR/session_hook.default.sh" <<EOF
#!/bin/bash
# Default session hook. Overwritten by setup-claude-service.sh, edit session_hook.user.sh instead.
echo "Deployment wrapper version: $SCRIPT_VERSION"
echo "Host: \$(hostname), user: \$(whoami), time: \$(date)"
[ -f "$TARGET_DIR/session_hook.user.sh" ] && /bin/bash "$TARGET_DIR/session_hook.user.sh"
[ -f "$TARGET_DIR/local_artifact.txt" ] && cat "$TARGET_DIR/local_artifact.txt"
exit 0
EOF

if [ ! -f "$TARGET_DIR/session_hook.user.sh" ]; then
    cat > "$TARGET_DIR/session_hook.user.sh" <<'EOF'
#!/bin/bash
# Your own session hook. Whatever it prints is added to Claude's context at session start.
# echo "Cores: $(nproc 2>/dev/null || sysctl -n hw.ncpu)"
EOF
fi

# 4. settings.json: merge into the existing file, keep everything else
python3 - "$TARGET_DIR/settings.json" "$TARGET_DIR/session_hook.default.sh" <<'EOF'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
try:
    s = json.load(open(path))
except Exception:
    s = {}
perm = s.setdefault("permissions", {})
allow = perm.setdefault("allow", [])
for t in ["Bash", "Read", "Edit", "Write", "WebFetch", "WebSearch"]:
    if t not in allow:
        allow.append(t)
cmd = "/bin/bash " + hook
hooks = s.setdefault("hooks", {}).setdefault("SessionStart", [])
if not any(h.get("command") == cmd for e in hooks for h in e.get("hooks", [])):
    hooks.append({"hooks": [{"type": "command", "command": cmd}]})
json.dump(s, open(path, "w"), indent=2)
EOF

# 4b. Config file (created once, never overwritten)
ENV_FILE="$TARGET_DIR/service.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<EOF
# Read by claude-bootstrap.sh every minute. Changes apply without re-running the installer.
# server  = "claude remote-control": this machine is listed as a computer in claude.ai/code,
#           sessions are opened from there. --continue reattaches only to a session from the last ~4 hours.
# session = "claude --continue --remote-control": one interactive session that always continues the
#           last conversation in WORK_DIR, but it is listed as a session, not as a computer.
CLAUDE_MODE="$CLAUDE_MODE"
# Name shown in claude.ai/code (server mode)
CLAUDE_NAME="$CLAUDE_NAME"
# Directory the session runs in
WORK_DIR="$WORK_DIR"
# Keep the machine awake while the session runs: yes (caffeinate on macOS, systemd-inhibit on Linux) or no
KEEP_AWAKE="$KEEP_AWAKE"
# Optional repo kept as a read-only copy in ~/.claude-service-repo (empty = off)
GIT_REPO_URL="$GIT_REPO_URL"
# Permission mode for the sessions: bypassPermissions (allow everything, no questions), acceptEdits, auto, default, dontAsk, plan.
# Empty = Claude's normal mode (asks before most tools).
CLAUDE_PERMISSION_MODE="$CLAUDE_PERMISSION_MODE"
EOF
    echo "Wrote $ENV_FILE"
else
    echo "Keeping existing $ENV_FILE"
fi

# 5. Watchdog script
cat > "$HOME/.local/bin/claude-bootstrap.sh" <<'EOF'
#!/bin/bash
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
TARGET_DIR="$HOME/.claude"
REPO_DIR="$HOME/.claude-service-repo"
ENV_FILE="$TARGET_DIR/service.env"
SESSION="claude-service"
CHECK_EVERY=60        # seconds between session checks
SYNC_EVERY=3600       # seconds between repo pulls
LOG="$TARGET_DIR/logs/daemon.log"
last_sync=0
running_mode=""

mkdir -p "$TARGET_DIR/logs"
exec >> "$TARGET_DIR/logs/daemon.log" 2>&1

CLAUDE=$(command -v claude)
TMUX=$(command -v tmux)
echo "[$(date)] Watchdog started"

while true; do
    # Defaults, then the config file
    CLAUDE_MODE=server; CLAUDE_NAME=$(hostname -s); WORK_DIR="$HOME"; GIT_REPO_URL=""; CLAUDE_PERMISSION_MODE=bypassPermissions; KEEP_AWAKE=no
    [ -f "$ENV_FILE" ] && . "$ENV_FILE"

    # Keep the log small
    [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 1000000 ] && tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"

    if [ -z "$CLAUDE" ] || ! "$CLAUDE" --version >/dev/null 2>&1; then
        echo "Claude binary missing or broken, retrying in 60 s"
        sleep 60
        CLAUDE=$(command -v claude)
        continue
    fi

    if curl -sI --max-time 10 https://api.anthropic.com/ >/dev/null; then
        # Keep a read-only copy of the repo (fast-forward only, never touches ~/.claude)
        now=$(date +%s)
        if [ -n "$GIT_REPO_URL" ] && [ $((now - last_sync)) -ge "$SYNC_EVERY" ]; then
            if [ -d "$REPO_DIR/.git" ]; then
                git -C "$REPO_DIR" pull --ff-only || echo "Git pull failed"
            else
                git clone "$GIT_REPO_URL" "$REPO_DIR" || echo "Git clone failed"
            fi
            last_sync=$now
        fi

        # Mode changed in the config file: stop the running session so it restarts in the new mode
        if [ -n "$running_mode" ] && [ "$running_mode" != "$CLAUDE_MODE" ] && "$TMUX" has-session -t "$SESSION" 2>/dev/null; then
            echo "[$(date)] Mode changed ($running_mode -> $CLAUDE_MODE), restarting"
            "$TMUX" kill-session -t "$SESSION"
        fi

        # Keep the session alive
        if ! "$TMUX" has-session -t "$SESSION" 2>/dev/null; then
            echo "[$(date)] Session missing, starting it in $CLAUDE_MODE mode"
            # Pre-answer Claude's one-time startup questions (onboarding, Remote Control, trust WORK_DIR,
            # CLAUDE.md includes, bypassPermissions warning), so a start with nobody attached never hangs
            python3 - "$HOME/.claude.json" "$WORK_DIR" "$CLAUDE_PERMISSION_MODE" <<'PY' || echo "Could not pre-answer the startup questions"
import json, os, sys
path, wd, pm = sys.argv[1], os.path.realpath(sys.argv[2]), sys.argv[3]
try:
    d = json.load(open(path))
except FileNotFoundError:
    d = {}
want = {"hasCompletedOnboarding": True, "remoteDialogSeen": True}
if pm == "bypassPermissions":
    want["bypassPermissionsModeAccepted"] = True
want_project = {"hasTrustDialogAccepted": True, "hasClaudeMdExternalIncludesApproved": True,
                "hasClaudeMdExternalIncludesWarningShown": True}
p = d.setdefault("projects", {}).setdefault(wd, {})
changed = [k for k, v in want.items() if d.get(k) != v] + [k for k, v in want_project.items() if p.get(k) != v]
if changed:
    d.update(want)
    p.update(want_project)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=2)
    os.chmod(tmp, os.stat(path).st_mode if os.path.exists(path) else 0o600)
    os.replace(tmp, path)
    print("Pre-answered for " + wd + ": " + ", ".join(changed))
PY
            PM=""; [ -n "$CLAUDE_PERMISSION_MODE" ] && PM="--permission-mode $CLAUDE_PERMISSION_MODE"
            if [ "$CLAUDE_MODE" = "session" ]; then
                CMD="'$CLAUDE' --continue --remote-control $PM || '$CLAUDE' --remote-control $PM"
            else
                CMD="'$CLAUDE' remote-control --name '$CLAUDE_NAME' $PM --continue || '$CLAUDE' remote-control --name '$CLAUDE_NAME' $PM"
            fi
            PREFIX=""
            if [ "$KEEP_AWAKE" = "yes" ]; then
                if command -v caffeinate >/dev/null; then PREFIX="caffeinate -is"
                elif command -v systemd-inhibit >/dev/null; then PREFIX="systemd-inhibit --what=idle:sleep --who=claude-service --why=Claude-background-session"
                else echo "KEEP_AWAKE=yes but neither caffeinate nor systemd-inhibit found"; fi
            fi
            if [ -n "$PREFIX" ]; then CMD="$PREFIX bash -c $(printf '%q' "$CMD")"; fi
            "$TMUX" new-session -d -s "$SESSION" -c "$WORK_DIR" "$CMD"
            running_mode="$CLAUDE_MODE"
            sleep 5
        fi

        # One-shot prompt injection
        if [ -f "$TARGET_DIR/on_start.txt" ] && "$TMUX" has-session -t "$SESSION" 2>/dev/null; then
            echo "Sending on_start.txt to the session"
            mv "$TARGET_DIR/on_start.txt" "$TARGET_DIR/on_start.txt.processed"
            "$TMUX" send-keys -t "$SESSION" "Read $TARGET_DIR/on_start.txt.processed and carry out the instructions in it." Enter
        fi
    else
        echo "[$(date)] No connection to api.anthropic.com, retrying"
    fi

    sleep "$CHECK_EVERY"
done
EOF
chmod +x "$HOME/.local/bin/claude-bootstrap.sh" "$TARGET_DIR/session_hook.default.sh" "$TARGET_DIR/session_hook.user.sh"

# 5b. Retire the older single-purpose unit (claude-rc.service) so two sessions do not fight over one conversation
if [ "$OS" == "linux" ] && systemctl --user list-unit-files claude-rc.service >/dev/null 2>&1 \
   && systemctl --user is-enabled claude-rc.service >/dev/null 2>&1; then
    echo "Disabling the old claude-rc.service"
    systemctl --user disable --now claude-rc.service || true
    tmux kill-session -t claude 2>/dev/null || true
fi

# 6. Autostart
if [ "$OS" == "mac" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.anthropic.claude.plist"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.anthropic.claude</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>$HOME/.local/bin/claude-bootstrap.sh</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
else
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    cat > "$SYSTEMD_DIR/claude.service" <<EOF
[Unit]
Description=Claude Code background session (Remote Control)
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash %h/.local/bin/claude-bootstrap.sh
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable claude.service
    systemctl --user restart claude.service
    loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q yes || sudo loginctl enable-linger "$USER"
fi

echo "Done. Sign in once with 'claude' if you have not yet. Log: $TARGET_DIR/logs/daemon.log"
echo "Attach to the session: tmux attach -t claude-service"
