#!/bin/bash
# git-auto-push.sh
# Stop hook: commit and push any vault changes to origin/main.
# Runs the push in the background so the Stop hook returns immediately.
# Logs to .git/auto-push.log for debugging.

VAULT_DIR="/Applications/Notes/SangDevLog"
LOG="$VAULT_DIR/.git/auto-push.log"

cd "$VAULT_DIR" || exit 0

# Not a git repo — no-op.
[ ! -d "$VAULT_DIR/.git" ] && exit 0

# Nothing to commit — no-op.
if [ -z "$(git status --porcelain)" ]; then
    exit 0
fi

# Build a compact commit body from the changed paths (cap at 20 lines).
changed=$(git status --porcelain | awk '{print $NF}' | head -20)
count=$(git status --porcelain | wc -l | tr -d ' ')
stamp=$(date "+%Y-%m-%d %H:%M")

msg="vault: auto-sync $count file(s) [$stamp]

$changed

Co-Authored-By: Claude Code <noreply@anthropic.com>"

{
    echo "=== $stamp ==="
    git add -A
    git commit -m "$msg" && git push origin main
    echo
} >> "$LOG" 2>&1 &

disown
exit 0
