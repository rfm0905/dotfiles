#!/bin/zsh
# End-to-end audit of obsidian-sync.zsh in a sandbox. Never touches the real
# vault or GitHub: builds a bare repo as origin and a scratch vault, then drives
# the real script (with VAULT rewritten) through each decision branch.
set -uo pipefail

ROOT=/tmp/obsidian-audit
rm -rf $ROOT 2>/dev/null
mkdir -p $ROOT
git init -q --bare $ROOT/origin.git
mkdir -p $ROOT/vault/{Notes,Journals,.obsidian/plugins/dataview,visuals}
cd $ROOT/vault
git init -q -b main .
git config user.email a@b.c; git config user.name audit
echo seed > Notes/seed.md
git add -A; git commit -q -m "seed"
git remote add origin $ROOT/origin.git
git push -q -u origin main

# the real script, pointed at the sandbox
sed "s|^VAULT=.*|VAULT=\"$ROOT/vault\"|" \
    $HOME/.local/bin/obsidian-sync.zsh > $ROOT/sync.zsh
chmod +x $ROOT/sync.zsh

run() { print -r -- "--- $1"; zsh $ROOT/sync.zsh 2>&1 | sed 's/^/      /'; }
backdate() {  # move HEAD's commit date back N hours
  local h=$1
  GIT_COMMITTER_DATE="$(date -v-${h}H '+%Y-%m-%dT%H:%M:%S%z')" \
  git commit -q --amend --no-edit --date="$(date -v-${h}H '+%Y-%m-%dT%H:%M:%S%z')"
  # Amending rewrites the hash, so the sandbox origin now looks AHEAD of local.
  # The script's fetch/rebase guard would then rebase onto origin and restore the
  # original date, silently defeating every age-based test. Force the sandbox
  # remote back into step. The real script never amends, so this is harness-only.
  git push -q -f origin main
}

print -r -- "=== 1. no changes =========================================="
run "expect: nothing changed"

print -r -- "=== 2. tiny note edit, recent commit ======================="
echo "one line" >> Notes/seed.md
run "expect: holding (1 authored line, fresh commit)"

print -r -- "=== 3. same edit, last commit 30h old ======================"
backdate 30
run "expect: commit via daily floor"
print -r -- "      subject: $(git log -1 --format=%s)"

print -r -- "=== 4. plugin-only change, commit 30h old =================="
echo '{"a":1}' > .obsidian/plugins/dataview/data.json
backdate 30
run "expect: holding (0 authored, under a week)"

print -r -- "=== 5. plugin-only change, commit 8 days old ==============="
backdate 192
run "expect: commit via weekly floor"
print -r -- "      subject: $(git log -1 --format=%s)"

print -r -- "=== 6. big note edit (>30 lines) ==========================="
for i in {1..40}; do echo "line $i" >> Notes/big.md; done
run "expect: immediate commit via churn"
print -r -- "      subject: $(git log -1 --format=%s)"

print -r -- "=== 7. journal template birth only (157 lines) ============="
for i in {1..157}; do echo "boilerplate $i" >> "Journals/11-14-2026.md"; done
backdate 30
run "expect: holding — template birth must NOT count as authored"

print -r -- "=== 8. journal EDIT (modified, not created) ================"
echo "real writing in the journal" >> "Journals/11-14-2026.md"
# Still 0 authored, and that is CORRECT. The note from test 7 was never
# committed, so to git it is still an addition (A), not a modification (M) --
# and CHURN_B counts only M. Writing in a brand-new journal therefore adds no
# churn until that note has been committed once, after which edits do count.
run "expect: holding, 0 authored — new journal is still 'A', not 'M'"

print -r -- "=== 9. iCloud duplicate warning ============================"
echo dup > visuals/img.png; git add -A; git commit -q -m "base img"
cp visuals/img.png "visuals/img 2.png"
for i in {1..40}; do echo "l $i" >> Notes/trigger.md; done
run "expect: WARN line naming 'visuals/img 2.png'"

print -r -- "=== 10. final state ========================================"
print -r -- "      commits: $(git rev-list --count HEAD)"
print -r -- "      pushed:  $(git rev-parse --short origin/main) == $(git rev-parse --short HEAD)"
print -r -- "      log:"
git log --format='        %s' | head -6
