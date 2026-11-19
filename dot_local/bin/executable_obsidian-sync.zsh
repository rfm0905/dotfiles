#!/bin/zsh
# Obsidian vault -> git. Single entry point; launchd polls this (StartInterval).
#
# TWO KINDS OF COMMIT
#
#   normal  - authored content only. Plugins and Journals are deliberately NOT
#             staged, because between them they produce ~90% of this repo's line
#             churn (a plugin main.js is thousands of lines; a fresh daily note
#             is ~157 lines of template) and none of it is writing.
#   weekly  - everything, including plugins and Journals, once every 7 days.
#             This is the only path that ever commits them.
#
# A normal commit happens when ALL of these hold:
#   1. nothing authored has been touched for QUIET_MIN minutes, AND
#   2. either authored churn >= THRESHOLD, or churn > 0 and the last commit
#      is >= DAY old.
#
# The quiet gate is the point of the whole design: without it an editing session
# trips the threshold on every single poll, which is how 11-17 produced seven
# commits between 4am and 7am. With it, a session collapses into one commit once
# Raed stops typing.
#
# TRIGGER is a whitelist, not a blacklist, on purpose: plugin dirs come and go
# constantly so an exclude list goes stale, while a list of things Raed types
# into does not.

set -uo pipefail

VAULT="$HOME/ObsidianNotes"
THRESHOLD=30            # authored lines that justify an immediate commit
QUIET_MIN=30            # minutes of no authored edits required before committing
DAY=$(( 24 * 3600 ))
WEEK=$(( 7 * 24 * 3600 ))
WSUBJ="Weekly Sync Plugins and Journals"

cd "$VAULT" || exit 1
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null) || BRANCH=main
NOW=$(date +%s)

# Plugins are never staged on the normal path. Journals are handled separately
# below, because they need per-file judgement rather than a blanket rule.
SKIP=( ':(exclude).obsidian/plugins/*' ':(exclude)Journals/*' )
TEMPLATE="xTemplates/daily.md"
JOURNAL_MIN=5           # lines a new journal must differ from the template by
JCHURN=0                # content lines from newly-staged journals

# Fetch every run: cheap, read-only, never touches the working tree.
# Only rebase when the remote actually moved — that is the operation that can
# conflict mid-session, so it must not fire 48 times a day for nothing.
git fetch -q origin "$BRANCH" 2>/dev/null
if (( $(git rev-list --count HEAD..origin/$BRANCH 2>/dev/null || echo 0) > 0 )); then
    # An UNTRACKED local file sitting at a path the incoming commits ADD makes
    # git refuse the rebase outright ("untracked working tree files would be
    # overwritten"), and autoStash does not cover untracked files. Left alone
    # that wedges this script on every run until someone notices by hand.
    # Rename rather than delete — the local copy may have something typed into
    # it, and a rename needs no permission.
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

# --- is the weekly plugins+journals sweep due? ---------------------------
# Timed off the last WEEKLY commit, not the last commit of any kind. Normal
# commits land often and would otherwise keep resetting the clock, so the sweep
# would never fire. No weekly commit in history at all => WLAST=0 => due now,
# which correctly flushes the current plugin and journal state on first run.
WLAST=$(git log -1 --format=%ct --grep="^${WSUBJ}" 2>/dev/null)
[[ -z "$WLAST" ]] && WLAST=0
if (( WLAST == 0 )); then
    # Never swept. NOW - 0 is seconds since the epoch — ~20,000 days — which
    # would read as wildly overdue and trip the starvation override below,
    # force-committing straight through the quiet gate on the very first run.
    # "Due, but not overdue" is the honest value: sweep at the next quiet moment.
    WAGE=$WEEK
else
    WAGE=$(( NOW - WLAST ))
fi
WEEKLY=0
(( WAGE >= WEEK )) && WEEKLY=1

# --- quiet gate ----------------------------------------------------------
# Most recent mtime across AUTHORED files only. Plugin dirs are excluded or the
# vault would never look quiet — they rewrite data.json every few minutes, which
# would block every commit forever.
# Gitignored files are skipped: they can never trigger a commit, so letting one
# block a commit is backwards. .DS_Store is the case that bit — macOS rewrites
# it whenever a Finder window changes, it lives inside xTemplates/ and Journals/,
# and it held the gate open indefinitely while nothing committable had changed.
ACTIVE=""
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    git check-ignore -q -- "$f" && continue
    ACTIVE="$f"
    break
done < <(find . -type f \
         \( -name '*.md' -o -path './.obsidian/snippets/*' -o -path './xTemplates/*' \) \
         -not -path './.git/*' -not -path './.obsidian/plugins/*' \
         -mmin -${QUIET_MIN} -print 2>/dev/null)

if [[ -n "$ACTIVE" ]]; then
    # The sweep may not starve: if someone edits something every 29 minutes for
    # days on end, force it through once it is a full day overdue.
    if (( WEEKLY && WAGE >= WEEK + DAY )); then
        echo "$(date): still active but weekly sweep $(( WAGE / DAY ))d overdue — forcing"
    else
        echo "$(date): holding — '${ACTIVE#./}' edited within ${QUIET_MIN}m"
        exit 0
    fi
fi

# --- stage ---------------------------------------------------------------
# The weekly sweep's job is to let PLUGINS through, nothing more. Journals obey
# the same content gate either way: a sweep that ran `git add -A` would commit
# empty template clones once a week and quietly undo the gate.
if (( WEEKLY )); then
    git add -A -- . ':(exclude)Journals/*'
else
    git add -A -- . $SKIP
fi

# Journals, two rules:
#
#   edits to a journal git already tracks  -> always staged (-u never adds
#                                             new files, only updates known
#                                             ones, so a birth cannot slip in)
#   a brand-new journal                    -> staged only once it differs
#                                             from the template by
#                                             JOURNAL_MIN lines
#
# A fresh daily note is a byte-for-byte copy of a 287-line template of which
# 271 lines are dataviewjs. Committing that on creation buys nothing and
# buries every real change. Waiting until there is actual writing in it means
# the boilerplate still lands once — unavoidable, git stores trees not
# patches — but attached to a note that has content.
# Guarded: with no journal tracked yet (a fresh clone) this pathspec matches
# nothing and git prints a fatal, which would land in the log every 30min.
if [[ -n "$(git ls-files -- 'Journals/*.md' | head -1)" ]]; then
    git add -u -- 'Journals/*.md'
fi

for f in ${(f)"$(git ls-files --others --exclude-standard -- 'Journals/*.md')"}; do
    [[ -n "$f" && -f "$f" ]] || continue
    if [[ -f "$TEMPLATE" ]]; then
        # Skip frontmatter on both sides: ID and 'date created' always differ
        # and would otherwise count as content.
        d=$(diff <(tail -n +8 "$TEMPLATE") <(tail -n +8 "$f") 2>/dev/null \
            | grep -c '^[<>]')
    else
        d=$JOURNAL_MIN      # no template to compare against: treat as real
    fi
    if (( d >= JOURNAL_MIN )); then
        git add -- "$f"
        # Carry the CONTENT line count, not the file's 287. A staged birth is
        # an 'A', so the modified-journals churn below cannot see it, and
        # without this a new note holding real writing scores zero churn —
        # failing both the threshold and the daily floor (which needs
        # churn > 0) and sitting uncommitted until the weekly sweep.
        JCHURN=$(( JCHURN + d ))
        echo "$(date): new journal ${f:t} has ${d} lines of content — staging"
    fi
done

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

# --- decide --------------------------------------------------------------
if (( WEEKLY )); then
    REASON="weekly sweep"
else
    TRIGGER=( '*.md' '.obsidian/snippets/*' 'xTemplates/*' )
    CHURN_A=$(git diff --cached --numstat --diff-filter=AMD -- $TRIGGER ':(exclude)Journals/*' \
              | awk -F'\t' '$1 != "-" {s += $1 + $2} END {print s+0}')
    # Journals count only when MODIFIED. A birth that cleared the content gate
    # above is still 287 staged lines, 271 of them template; letting that reach
    # the threshold would make every new note force an instant commit and put
    # the boilerplate right back in charge of the trigger.
    CHURN_B=$(git diff --cached --numstat --diff-filter=M -- 'Journals/*.md' \
              | awk -F'\t' '$1 != "-" {s += $1 + $2} END {print s+0}')
    CHURN=$(( CHURN_A + CHURN_B + JCHURN ))

    LAST=$(git log -1 --format=%ct 2>/dev/null) || LAST=0
    AGE=$(( NOW - LAST ))

    if   (( CHURN >= THRESHOLD ));      then REASON="churn ${CHURN}"
    elif (( CHURN > 0 && AGE >= DAY )); then REASON="daily floor (${CHURN} authored)"
    else
        git reset -q
        echo "$(date): holding — ${CHURN} authored lines, last commit $(( AGE / 3600 ))h ago"
        exit 0
    fi
fi

# --- commit message ------------------------------------------------------
STAMP=$(date '+%-m-%-d-%y %-I:%M %p')

if (( WEEKLY )); then
    SUBJECT="${WSUBJ} - $(date '+%-m-%-d-%y')"
else
    TITLES=( ${(f)"$({ git diff --cached --name-only --diff-filter=A -- '*.md' ':(exclude)Journals/*'
                       git diff --cached --name-only --diff-filter=M -- '*.md' ':(exclude)Journals/*' } \
                     | sed 's|.*/||; s|\.md$||')"} )
    TITLES=( ${TITLES:#} )

    BUCKETS=( ${(fu)"$(git diff --cached --name-only \
                       | sed -n -e 's|^\.obsidian/snippets/.*|snippets|p' \
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
    SUBJECT="Sync: $STAMP${WHAT:+ — $WHAT}"
fi

git commit -q -m "$SUBJECT" \
              -m "$(git diff --cached --name-status)" \
              -m "[$REASON]"

# autoStash is required now, not optional: on the normal path plugins and
# Journals are left uncommitted by design, so the working tree is ALWAYS dirty
# and a plain pull --rebase would refuse with "you have unstaged changes".
if ! git -c rebase.autoStash=true pull --rebase origin "$BRANCH"; then
    git rebase --abort 2>/dev/null
    echo "$(date): rebase conflict, aborted — not pushing"
    exit 1
fi

git push origin "$BRANCH" && echo "$(date): pushed — $REASON"
