#!/bin/bash
set -e

# === CONFIGURATION ===
SCRIPT_VERSION="1.6.0"
GIT_REPO_URL="https://github.com/YOUR-USERNAME/claude-automation-tasks.git"
TARGET_DIR="$HOME/.claude"
# =====================

echo "🚀 Starting Native Multi-OS Deployment (Version $SCRIPT_VERSION)..."

# 1. OS Detection & Local Bin Prep
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="mac"
    echo "💻 macOS detected."
    if ! command -v tmux &> /dev/null; then
        echo "⚠️ tmux is missing. Please ensure tmux is installed on your Mac."
    fi
else
    OS="linux"
    echo "🐧 Linux (Debian/Ubuntu) detected."
    sudo apt-get update && sudo apt-get install -y build-essential curl git tmux
fi

# 2. Native Claude Code Installation
if ! command -v claude &> /dev/null && [ ! -f "$HOME/.local/bin/claude" ]; then
    echo "📦 Claude Code not found. Running official native installer..."
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "📦 Claude Code is already installed."
fi

# 3. Create Runtime Directory and Modular Hooks
mkdir -p "$TARGET_DIR"

echo "📝 Writing immutable default session hook..."
cat << EOF > "$TARGET_DIR/session_hook.default.sh"
#!/bin/bash
# =====================================================================
# CLAUDE CODE DEFAULT HOOK (Do not edit - overwritten on update)
# =====================================================================
echo "=== SYSTEM INITIALIZATION ==="
echo "Deployment Wrapper Version: $SCRIPT_VERSION"
echo "Host Machine Node: \$(hostname)"
echo "Executing User Context: \$(whoami)"
echo "Current Timestamp: \$(date)"
echo "-------------------------------------"

# Dynamically chain user-defined hooks if they exist
if [ -f "$TARGET_DIR/session_hook.user.sh" ]; then
    /bin/bash "$TARGET_DIR/session_hook.user.sh"
fi

# Dynamically chain local optional artifact templates if they exist
if [ -f "$TARGET_DIR/local_artifact.txt" ]; then
    echo "Local Node Artifacts Detected:"
    cat "$TARGET_DIR/local_artifact.txt"
fi
echo "====================================="
EOF

# Create the user sandbox hook ONLY if it does not exist yet (Idempotent Guard)
if [ ! -f "$TARGET_DIR/session_hook.user.sh" ]; then
    echo "📝 Creating customizable user session hook sandbox..."
    cat << 'EOF' > "$TARGET_DIR/session_hook.user.sh"
#!/bin/bash
# =====================================================================
# USER SESSION HOOK SANDBOX (Edit freely for local modifications)
# Any strings echoed here are fed directly into Claude's prompt context.
# =====================================================================

# EXAMPLE 1: Reading machine name to execute localized tasks
# MACHINE_NAME=$(hostname)
# echo "Custom logic running for node: $MACHINE_NAME"

# EXAMPLE 2: Reading host hardware parameters
# if [[ "$OSTYPE" == "darwin"* ]]; then
#     echo "Available Cores: $(sysctl -n hw.ncpu)"
# else
#     echo "Available Cores: $(nproc)"
# fi
EOF
fi

echo "🔐 Configuring Claude internal settings & mapping entry hook..."
cat << EOF > "$TARGET_DIR/settings.json"
{
  "autoMode": {
    "enabled": true,
    "allowAllCommands": true,
    "allowAllFileEdits": true,
    "allowAllRiskLevels": true
  },
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "/bin/bash $TARGET_DIR/session_hook.default.sh"
      }
    ]
  }
}
EOF

# 4. Create the Universal Hourly Bootstrap Script
echo "📝 Writing native session management script..."

cat << 'EOF' > "$HOME/.local/bin/claude-bootstrap.sh"
#!/bin/bash
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
TARGET_DIR="$HOME/.claude"

mkdir -p "$TARGET_DIR/logs"
chmod -R 755 "$TARGET_DIR" 2>/dev/null || true
exec >> "$TARGET_DIR/logs/daemon.log" 2>&1

CLAUDE_PATH=$(which claude)
TMUX_PATH=$(which tmux)
HOURLY_DELAY=3600  # 1 hour in seconds

echo "[Service] [$(date)] Watchdog daemon activated inside native runtime folder..."

while true; do
    echo "⏰ [$(date)] Executing maintenance and session validation check..."

    # Enforce clean executable flags across the modular engine setup
    chmod -R 755 "$TARGET_DIR" 2>/dev/null || true
    chmod +x "$HOME/.local/bin/claude-bootstrap.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/session_hook.default.sh" 2>/dev/null || true
    if [ -f "$TARGET_DIR/session_hook.user.sh" ]; then chmod +x "$TARGET_DIR/session_hook.user.sh" 2>/dev/null || true; fi
    if [ -f "$CLAUDE_PATH" ]; then chmod +x "$CLAUDE_PATH" 2>/dev/null || true; fi

    # A. Check if Claude binary works
    if ! $CLAUDE_PATH --help > /dev/null 2>&1; then
        echo "⚠️ [Security Check] Claude binary execution failed or missing dependencies."
        sleep 10
        continue
    fi

    # B. Continuous Network Checking
    if curl -sI --max-time 10 https://api.anthropic.com/ > /dev/null; then
        echo "[Network] Connection successful."

        # C. Sync upstream tasks straight into ~/.claude
        if [ ! -d "$TARGET_DIR/.git" ]; then
            echo "[Git] Initializing repository for tasks in native path..."
            git clone "GIT_REPO_URL_PLACEHOLDER" "$TARGET_DIR/repo_tmp" 2>/dev/null &&             mv "$TARGET_DIR/repo_tmp/.git" "$TARGET_DIR/" &&             rm -rf "$TARGET_DIR/repo_tmp" || true
            chmod -R 755 "$TARGET_DIR" 2>/dev/null || true
        fi

        if [ -d "$TARGET_DIR/.git" ]; then
            echo "[Git] Pulling latest changes..."
            cd "$TARGET_DIR"
            git fetch --all && git reset --hard origin/\$(git branch --show-current) && git pull
            chmod -R 755 "$TARGET_DIR" 2>/dev/null || true
        fi

        # D. Maintain the Tmux Instance with Strict Auto Mode Enabled
        $TMUX_PATH has-session -t claude-service 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "[Service] 🚨 Watchdog alert: Claude background session was missing! Restarting remote control environment..."
            $TMUX_PATH new-session -d -s claude-service "cd $TARGET_DIR && $CLAUDE_PATH --enable-auto-mode"
            sleep 5
        else
            echo "[Service] Active session validation passed. Remote control is alive."
        fi

        # E. Feed new commands if an instruction file is present
        if [ -f "$TARGET_DIR/on_start.txt" ]; then
            echo "[Service] Injecting prompts from on_start.txt into the active session..."
            $TMUX_PATH send-keys -t claude-service "Read files and execute prompts from on_start.txt" Enter
            mv "$TARGET_DIR/on_start.txt" "$TARGET_DIR/on_start.txt.processed" 2>/dev/null || true
            chmod 755 "$TARGET_DIR/on_start.txt.processed" 2>/dev/null || true
        fi

    else
        echo "❌ [Network] Connection to api.anthropic.com failed. Skipping Git/Session sync. Watchdog will re-evaluate."
    fi

    sleep $HOURLY_DELAY
done
EOF

# Inject the defined Git Repo URL dynamically into the script string
sed -i.bak "s|GIT_REPO_URL_PLACEHOLDER|$GIT_REPO_URL|g" "$HOME/.local/bin/claude-bootstrap.sh" 2>/dev/null || sed -i "" "s|GIT_REPO_URL_PLACEHOLDER|$GIT_REPO_URL|g" "$HOME/.local/bin/claude-bootstrap.sh"
rm -f "$HOME/.local/bin/claude-bootstrap.sh.bak"

# 5. Enforce Permissions on Setup Level
chmod +x "$HOME/.local/bin/claude-bootstrap.sh"
chmod +x "$TARGET_DIR/session_hook.default.sh"
if [ -f "$TARGET_DIR/session_hook.user.sh" ]; then chmod +x "$TARGET_DIR/session_hook.user.sh"; fi
chmod -R 755 "$TARGET_DIR"

# 6. Setup Native OS Autostart Mechanics with Strict Restart Policies
if [ "$OS" == "mac" ]; then
    echo "⚙️ Configuring macOS LaunchAgent with strict KeepAlive..."
    PLIST="$HOME/Library/LaunchAgents/com.anthropic.claude.plist"
    cat << EOF > "$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.anthropic.claude</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>$HOME/.local/bin/claude-bootstrap.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
else
    echo "⚙️ Configuring Linux Systemd User-Service with Restart enforcement..."
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    cat << EOF > "$SYSTEMD_DIR/claude.service"
[Unit]
Description=Claude Code Native Background Continuous Service
After=network.target

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
    sudo loginctl enable-linger $USER
fi

echo "✅ Modular deployment complete! Edit custom configurations safely inside ~/.claude/session_hook.sh"
