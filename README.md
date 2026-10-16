# Unattended Claude Code Background Service with Git Sync

A cross-platform, zero-dependency provisioning and automation wrapper designed to deploy **Claude Code** as an always-on, unattended background service on **macOS** and **Linux (Debian/Ubuntu)**.

---

## 📂 Architecture Overview

The installation provisions a modular and highly secure directory structure directly inside Claude's native configurations directory:

```text
~/.claude/
├── settings.json              # Permissive autoMode definitions and static entry hooks
├── session_hook.default.sh    # SYSTEM MANAGED: Overwritten on update. Contains wrapper versions.
├── session_hook.user.sh       # USER SANDBOX: Created once. Safe to edit locally for system metrics.
├── local_artifact.txt         # Custom host metadata strings
└── logs/
    └── daemon.log             # Real-time orchestration log data
```

## 🚀 Execution & Quickstart

1. Configure your central task tracking link inside `setup-claude-service.sh`.
2. Run the executable payload script: `./setup-claude-service.sh`
3. Authenticate the agent once natively using your chosen profile terminal (`claude`).

## 🪝 Modular Session Hooks

- **`session_hook.default.sh`:** Handles execution metadata logging during automated reboots and ensures your engine parameters are safely compiled.
- **`session_hook.user.sh`:** Feel free to locally script host evaluations here utilizing commands dependent on `$(hostname)` or `$(whoami)`.

---
