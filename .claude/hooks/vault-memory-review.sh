#!/bin/bash
# vault-memory-review.sh
# Stop hook: if new/edited notes exist under Tech/ since the last review,
# tell Claude to review them and update memory files if anything new was learned
# about the user, project, or their preferences.

SENTINEL="/Users/sangdev/.claude/projects/-Applications-Notes-SangDevLog/memory/.last_review"
VAULT_DIR="/Applications/Notes/SangDevLog/Tech"

# Vault not present (running Claude Code from another checkout) — no-op.
[ ! -d "$VAULT_DIR" ] && exit 0

# First run: create sentinel and exit silently.
if [ ! -f "$SENTINEL" ]; then
    mkdir -p "$(dirname "$SENTINEL")"
    touch "$SENTINEL"
    exit 0
fi

# List notes edited since last review (cap at 5 lines to keep the reason compact).
recent=$(find "$VAULT_DIR" -type f -name "*.md" -newer "$SENTINEL" 2>/dev/null | head -5)

if [ -n "$recent" ]; then
    touch "$SENTINEL"
    jq -cn --arg files "$recent" '{
        decision: "block",
        reason: (
            "New/edited vault notes since last review:\n" + $files +
            "\n\nReview these additions and update memory files under " +
            "/Users/sangdev/.claude/projects/-Applications-Notes-SangDevLog/memory/ " +
            "IF they revealed anything new about the user, project, or their preferences " +
            "(per memory system rules — no duplicates, no code patterns, " +
            "no vault conventions already in CLAUDE.md). " +
            "If nothing new to memorize, acknowledge in one sentence and stop."
        )
    }'
fi
