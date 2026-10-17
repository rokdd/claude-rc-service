#!/bin/bash
# Example user session hook. Copy it as-is:
#   cp examples/session_hook.user.sh ~/.claude/session_hook.user.sh
# Whatever it prints goes into Claude's context at every session start.
# Turn a feature off by setting it to no here (or in ~/.claude/service.env).

# === SETTINGS ===
HANDOVER=yes       # keep handover notes in ~/.claude/CLAUDE.md, so another session can take over at any time
TOPICS=yes         # special topics live in ~/.claude/topics/*.md; Claude offers to load one at start
MACHINE_INFO=yes   # print OS, cores and free disk space
TELL_USER=yes      # Claude tells the user once per session what is on and how to opt out
# ================

[ -f "$HOME/.claude/service.env" ] && . "$HOME/.claude/service.env"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TOPICS_DIR="$HOME/.claude/topics"
on=""

if [ "$MACHINE_INFO" = "yes" ]; then
    on="$on, machine info"
    echo "OS: $(uname -sr), cores: $(nproc 2>/dev/null || sysctl -n hw.ncpu), disk free in home: $(df -h "$HOME" | awk 'NR==2 {print $4}')"
fi

if [ "$HANDOVER" = "yes" ]; then
    on="$on, handover"
    echo "Handover: keep the Handover section in $CLAUDE_MD current (state, open tasks, where things live), so another session can take over at any time. Update it right after each change that matters. Put longer write-ups in Claude artifacts and list their claude.ai links there; read a listed artifact only when the task needs it."
    [ -f "$CLAUDE_MD" ] || echo "$CLAUDE_MD does not exist yet: create it with a short '# This machine' intro and a '## Handover' section."
fi

if [ "$TOPICS" = "yes" ]; then
    on="$on, topics"
    echo "Topics: keep CLAUDE.md short. Details about one special subject (a script, a service, a project) go into $TOPICS_DIR/<topic>.md, first line '# <title>'. Only load a topic file when it is needed or the user picks it."
    if ls "$TOPICS_DIR"/*.md >/dev/null 2>&1; then
        echo "Available topics (offer the user to load one at the start of the session):"
        for f in "$TOPICS_DIR"/*.md; do
            echo "- $(basename "$f" .md): $(head -n 1 "$f" | sed 's/^# *//')"
        done
    else
        echo "No topic files yet."
    fi
fi

if [ "$TELL_USER" = "yes" ] && [ -n "$on" ]; then
    echo "Tell the user once, in your first reply, in one short line: this session hook is on (${on#, }) and they can opt out by setting a feature to no in ~/.claude/session_hook.user.sh (or TELL_USER=no to stop this notice)."
fi
exit 0
