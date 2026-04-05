#!/bin/zsh

VAULT="/Users/raedm/ObsidianNotes"

cd "$VAULT" || exit 1

# Pull first to avoid conflicts
git pull --rebase origin main 2>&1

# Stage all changes
git add -A

# Only commit if there's something to commit
if ! git diff --cached --quiet; then
    git commit -m "auto-sync: $(date '+%Y-%m-%d %H:%M')"
    git push origin main
fi
