#!/bin/bash
# Installs Claude Code as an always-on background service (macOS LaunchAgent / Linux systemd user unit).
# It keeps one Claude session alive in tmux with Remote Control, continuing the last conversation.
set -e

# === CONFIGURATION (override with environment variables) ===
SCRIPT_VERSION="2.0.0"
# Repo with shared hooks/tasks. Private repo: use an SSH URL with a deploy key, or a URL with a read-only token.
# Leave empty to skip syncing.
GIT_REPO_URL="${GIT_REPO_URL:-https://git.example.com/robert/claude-rc-service.git}"
# Directory the session runs in (its conversations are continued per directory).
WORK_DIR="${WORK_DIR:-$HOME}"
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

# 5. Watchdog script
cat > "$HOME/.local/bin/claude-bootstrap.sh" <<'EOF'
#!/bin/bash
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH"
TARGET_DIR="$HOME/.claude"
REPO_DIR="$HOME/.claude-service-repo"
GIT_REPO_URL="__GIT_REPO_URL__"
WORK_DIR="__WORK_DIR__"
SESSION="claude-service"
INTERVAL=3600

mkdir -p "$TARGET_DIR/logs"
exec >> "$TARGET_DIR/logs/daemon.log" 2>&1

CLAUDE=$(command -v claude)
TMUX=$(command -v tmux)
echo "[$(date)] Watchdog started"

while true; do
    echo "[$(date)] Check"

    if [ -z "$CLAUDE" ] || ! "$CLAUDE" --version >/dev/null 2>&1; then
        echo "Claude binary missing or broken, retrying in 60 s"
        sleep 60
        CLAUDE=$(command -v claude)
        continue
    fi

    if curl -sI --max-time 10 https://api.anthropic.com/ >/dev/null; then
        # Keep a read-only copy of the repo (fast-forward only, never touches ~/.claude)
        if [ -n "$GIT_REPO_URL" ]; then
            if [ -d "$REPO_DIR/.git" ]; then
                git -C "$REPO_DIR" pull --ff-only || echo "Git pull failed"
            else
                git clone "$GIT_REPO_URL" "$REPO_DIR" || echo "Git clone failed"
            fi
        fi

        # Keep the session alive: continue the last conversation with Remote Control, else start a new one
        if ! "$TMUX" has-session -t "$SESSION" 2>/dev/null; then
            echo "Session missing, starting it"
            "$TMUX" new-session -d -s "$SESSION" -c "$WORK_DIR" \
                "'$CLAUDE' --continue --remote-control || '$CLAUDE' --remote-control"
            sleep 5
        else
            echo "Session alive"
        fi

        # One-shot prompt injection
        if [ -f "$TARGET_DIR/on_start.txt" ] && "$TMUX" has-session -t "$SESSION" 2>/dev/null; then
            echo "Sending on_start.txt to the session"
            mv "$TARGET_DIR/on_start.txt" "$TARGET_DIR/on_start.txt.processed"
            "$TMUX" send-keys -t "$SESSION" "Read $TARGET_DIR/on_start.txt.processed and carry out the instructions in it." Enter
        fi
    else
        echo "No connection to api.anthropic.com, skipping"
    fi

    sleep "$INTERVAL"
done
EOF
sed -i.bak -e "s|__GIT_REPO_URL__|$GIT_REPO_URL|" -e "s|__WORK_DIR__|$WORK_DIR|" "$HOME/.local/bin/claude-bootstrap.sh"
rm -f "$HOME/.local/bin/claude-bootstrap.sh.bak"
chmod +x "$HOME/.local/bin/claude-bootstrap.sh" "$TARGET_DIR/session_hook.default.sh" "$TARGET_DIR/session_hook.user.sh"

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
    sudo loginctl enable-linger "$USER"
fi

echo "Done. Sign in once with 'claude' if you have not yet. Log: $TARGET_DIR/logs/daemon.log"
echo "Attach to the session: tmux attach -t claude-service"
