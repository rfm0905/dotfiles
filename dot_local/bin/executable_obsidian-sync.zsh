#!/bin/zsh
# Obsidian vault -> git. Single entry point; launchd polls this (StartInterval).
#
# Three ways a commit happens, checked in order:
#   1. authored churn >= THRESHOLD            -> commit now
#   2. any authored change at all, >= DAY old -> commit (daily floor)
#   3. nothing authored, but >= WEEK old      -> commit (weekly floor)
# Everything staged is committed either way; these only decide WHEN.
#
# Tier 3 exists because plugin code and daily-note templates generate ~90% of
# this repo's line churn. Without it, every single day produced a commit whose
# entire content was a plugin changelog. With it, those batch up weekly and the
# daily rhythm belongs to actual writing.
#
# TRIGGER is a whitelist, not a blacklist, on purpose: plugin dirs come and go
# constantly so an exclude list goes stale, while a list of things Raed types
# into does not.

set -uo pipefail

VAULT="$HOME/ObsidianNotes"
THRESHOLD=30
DAY=$(( 24 * 3600 ))
WEEK=$(( 7 * 24 * 3600 ))

cd "$VAULT" || exit 1
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null) || BRANCH=main

# Fetch every run: cheap, read-only, never touches the working tree.
# Only rebase when the remote actually moved — that is the operation that can
# conflict mid-session, so it must not fire 48 times a day for nothing.
# Without this the script only ever pulled right before a push, so anything
# written remotely (the Claude report notes) sat on the remote until the next
# local commit — up to a week on the weekly floor.
git fetch -q origin "$BRANCH" 2>/dev/null
if (( $(git rev-list --count HEAD..origin/$BRANCH 2>/dev/null || echo 0) > 0 )); then
    # An UNTRACKED local file sitting at a path the incoming commits ADD makes
    # git refuse the rebase outright ("untracked working tree files would be
    # overwritten"), and autoStash does not cover untracked files. Left alone
    # that wedges this script on every run until someone notices by hand.
    #
    # It has one real cause: the Claude report task creates today's journal note
    # on the remote, and the daily-notes plugin creates the same path locally
    # before the next poll pulls it down. Rename rather than delete — the local
    # copy may have something typed into it, and a rename needs no permission.
    for f in ${(f)"$(git diff --name-only --diff-filter=A HEAD..origin/$BRANCH 2>/dev/null)"}; do
        [[ -n "$f" && -e "$f" ]] || continue
        git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && continue
        mv -- "$f" "${f%.md}.local-$(date +%Y%m%d%H%M%S).md" 2>/dev/null \
            && echo "$(date): moved untracked $f aside for incoming remote copy"
    done
    if ! git -c rebase.autoStash=true pull --rebase origin "$BRANCH"; then
        git rebase --abort 2>/dev/null
        echo "$(date): pull conflict, aborted — nothing committed"
        exit 1
    fi
    echo "$(date): pulled remote changes"
fi

git add -A

if git diff --cached --quiet; then
    echo "$(date): nothing changed"
    exit 0
fi

# --- warn about new iCloud conflict copies -------------------------------
# Only flags a new file whose twin already exists AND is byte-identical.
# A differing twin is usually Obsidian auto-numbering a name that was taken,
# which is a real distinct note, so those are left alone silently.
git diff --cached --name-only --diff-filter=A | while IFS= read -r f; do
    if [[ "${f:t}" =~ '^(.*) ([0-9]+)(\.[^.]*)?$' ]]; then
        base="${f:h}/${match[1]}${match[3]}"
        if [[ -f "$base" ]] && cmp -s "$f" "$base"; then
            echo "$(date): WARN iCloud conflict copy — '$f' is identical to '$base'"
        fi
    fi
done

# --- decide whether to commit now ----------------------------------------
# Authored = notes, hand-written snippets, templates. A fresh
# Journals/MM-DD-YYYY.md is ~157 lines of plugin boilerplate, so journal files
# count only when MODIFIED, never when created.
TRIGGER=( '*.md' '.obsidian/snippets/*' 'xTemplates/*' )

CHURN_A=$(git diff --cached --numstat --diff-filter=AMD -- $TRIGGER ':(exclude)Journals/*' \
          | awk -F'\t' '$1 != "-" {s += $1 + $2} END {print s+0}')
CHURN_B=$(git diff --cached --numstat --diff-filter=M -- 'Journals/*.md' \
          | awk -F'\t' '$1 != "-" {s += $1 + $2} END {print s+0}')
CHURN=$(( CHURN_A + CHURN_B ))

LAST=$(git log -1 --format=%ct 2>/dev/null) || LAST=0
AGE=$(( $(date +%s) - LAST ))

if   (( CHURN >= THRESHOLD ));        then REASON="churn ${CHURN}"
elif (( CHURN > 0 && AGE >= DAY ));   then REASON="daily floor (${CHURN} authored)"
elif (( AGE >= WEEK ));               then REASON="weekly floor (no authored changes)"
else
    git reset -q
    echo "$(date): holding — ${CHURN} authored lines, last commit $(( AGE / 3600 ))h ago"
    exit 0
fi

# --- commit message: timestamp, note titles, then one word per folder -----
STAMP=$(date '+%-m-%-d-%y %-I:%M %p')

TITLES=( ${(f)"$({ git diff --cached --name-only --diff-filter=A -- '*.md' ':(exclude)Journals/*'
                   git diff --cached --name-only --diff-filter=M -- '*.md' ':(exclude)Journals/*' } \
                 | sed 's|.*/||; s|\.md$||')"} )
TITLES=( ${TITLES:#} )

BUCKETS=( ${(fu)"$(git diff --cached --name-only \
                   | sed -n -e 's|^\.obsidian/plugins/.*|plugins|p' \
                            -e 's|^\.obsidian/snippets/.*|snippets|p' \
                            -e 's|^\.obsidian/themes/.*|themes|p' \
                            -e 's|^\.obsidian/.*|config|p' \
                            -e 's|^visuals/.*|visuals|p' \
                            -e 's|^Clippings/.*|clippings|p' \
                            -e 's|^Excalidraw/.*|excalidraw|p' \
                            -e 's|^xTemplates/.*|templates|p' \
                            -e 's|^Journals/.*|journal|p')"} )
BUCKETS=( ${BUCKETS:#} )

PARTS=()
if (( $#TITLES )); then
    SHOWN=${(j:, :)TITLES[1,3]}
    (( $#TITLES > 3 )) && SHOWN="$SHOWN (+$(( $#TITLES - 3 )) more)"
    PARTS+=( "$SHOWN" )
fi
(( $#BUCKETS )) && PARTS+=( "${(j:, :)BUCKETS}" )
WHAT=${(j:, :)PARTS}

git commit -q -m "Sync: $STAMP${WHAT:+ — $WHAT}" \
              -m "$(git diff --cached --name-status)" \
              -m "[$REASON]"

if ! git pull --rebase origin "$BRANCH"; then
    git rebase --abort 2>/dev/null
    echo "$(date): rebase conflict, aborted — not pushing"
    exit 1
fi

git push origin "$BRANCH" && echo "$(date): pushed — $REASON"
