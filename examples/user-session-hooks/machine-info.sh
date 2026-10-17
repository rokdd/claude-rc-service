#!/bin/bash
# Example user session hook: a few facts about the machine.
# Use: copy the lines you want into ~/.claude/session_hook.user.sh.
echo "OS: $(uname -sr), cores: $(nproc 2>/dev/null || sysctl -n hw.ncpu)"
echo "Disk free in home: $(df -h "$HOME" | awk 'NR==2 {print $4}')"
