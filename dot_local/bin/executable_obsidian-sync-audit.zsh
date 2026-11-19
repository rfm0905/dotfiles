#!/bin/zsh
# End-to-end audit of obsidian-sync.zsh in a sandbox. Never touches the real
# vault or GitHub: builds a bare repo as origin and a scratch vault, then drives
# the real script (with VAULT rewritten) through each decision branch.
#
# Each case prints EXPECT and GOT so a mismatch is obvious without reading code.
set -uo pipefail

ROOT=${OBSIDIAN_AUDIT_ROOT:-/tmp/obsidian-audit}
SCRIPT=$HOME/.local/bin/obsidian-sync.zsh
TEMPLATE=$HOME/ObsidianNotes/xTemplates/daily.md

rm -rf $ROOT 2>/dev/null
mkdir -p $ROOT
git init -q --bare $ROOT/origin.git
mkdir -p $ROOT/vault/{Notes,Journals/2026-11,.obsidian/plugins/dataview,.obsidian/snippets,xTemplates,visuals}
cd $ROOT/vault
git init -q -b main .
git config user.email a@b.c; git config user.name audit

# The journal content gate diffs against the real template, so the sandbox needs
# a real one. Fall back to a stub if the vault is not on this machine.
if [[ -f "$TEMPLATE" ]]; then cp "$TEMPLATE" xTemplates/daily.md
else printf -- '---\nID:\ndate created: 06-12-2026\n---\n'; for i in {1..283}; do echo "boilerplate $i"; done > xTemplates/daily.md
fi

echo seed > Notes/seed.md
echo '{"a":0}' > .obsidian/plugins/dataview/data.json
git add -A; git commit -q -m "seed"
git remote add origin $ROOT/origin.git
git push -q -u origin main

sed "s|^VAULT=.*|VAULT=\"$ROOT/vault\"|" "$SCRIPT" > $ROOT/sync.zsh
chmod +x $ROOT/sync.zsh

# --- helpers -------------------------------------------------------------

# The quiet gate reads mtimes of authored files. Backdate them all so the gate
# opens; without this every case would just report "edited within 30m".
quiet() {
  find . -type f \( -name '*.md' -o -path './.obsidian/snippets/*' -o -path './xTemplates/*' \) \
    -not -path './.git/*' -not -path './.obsidian/plugins/*' \
    -exec touch -t 202601010000 {} \; 2>/dev/null
}

# Move HEAD's commit date back N hours.
# Amending rewrites the hash, so the sandbox origin then looks AHEAD of local and
# the script's fetch/rebase guard would rebase onto it, restoring the original
# date and silently defeating every age-based test. Force the remote back into
# step. The real script never amends, so this is harness-only.
backdate() {
  local h=$1
  GIT_COMMITTER_DATE="$(date -v-${h}H '+%Y-%m-%dT%H:%M:%S%z')" \
  git commit -q --amend --no-edit --date="$(date -v-${h}H '+%Y-%m-%dT%H:%M:%S%z')"
  git push -q -f origin main
}

run() { zsh $ROOT/sync.zsh 2>&1 | grep -vE '^(From|To) |^ \* branch|^Current branch|^   [0-9a-f]+\.\.' | sed 's/^/      /'; }
case_() { print -r -- "=== $1"; print -r -- "    EXPECT: $2"; }
state() {
  print -r -- "    STATE : journals=$(git ls-files 'Journals/*.md' | wc -l | tr -d ' ')" \
              "plugins=$(git ls-files '.obsidian/plugins/*' | wc -l | tr -d ' ')" \
              "| last: $(git log -1 --format=%s)"
}

# --- cases ---------------------------------------------------------------

case_ "1. nothing changed" "no commit"
quiet; run; state

case_ "2. QUIET GATE — authored file touched just now" "holding, 'edited within 30m'"
echo "typing right now" >> Notes/seed.md
run; state

case_ "3. first run ever is a WEEKLY SWEEP (no weekly commit in history)" "pushed — weekly sweep; plugins become tracked"
quiet; run; state

# Must happen HERE, while the weekly commit is still HEAD: backdate() amends
# HEAD, and the sweep clock reads the last WEEKLY commit specifically. Run this
# any later and it would backdate some ordinary Sync commit, no sweep would come
# due, and the case would pass vacuously.
case_ "4. EMPTY journal birth during a WEEKLY SWEEP" "sweep runs, but journal stays untracked"
cp xTemplates/daily.md Journals/2026-11/11-18-2026.md
echo '{"b":1}' >> .obsidian/plugins/dataview/data.json
backdate 200
quiet; run; state
rm -f Journals/2026-11/11-18-2026.md

case_ "5. small authored edit, commit is fresh" "holding, under threshold"
echo "one line" >> Notes/seed.md
quiet; run; state

case_ "6. same edit, last commit 30h old" "pushed — daily floor"
backdate 30
quiet; run; state

case_ "7. plugin-only change on the NORMAL path" "nothing changed — plugins never ride the normal path"
for i in {1..80}; do echo "{\"n\":$i}" >> .obsidian/plugins/dataview/data.json; done
backdate 30
quiet; run; state

case_ "8. big authored edit (>30 lines)" "pushed — churn, and still no plugin lines in it"
for i in {1..40}; do echo "line $i" >> Notes/big.md; done
quiet; run
print -r -- "    GOT   : plugin paths in that commit = $(git show --name-only --format='' HEAD | grep -c 'plugins/')  (want 0)"
state

case_ "9. EMPTY journal birth (byte-identical to template)" "never staged — not on the normal path"
cp xTemplates/daily.md Journals/2026-11/11-18-2026.md
quiet; run; state

case_ "10. journal gains 6 lines of real content" "staged, JCHURN=6 counted"
for i in {1..6}; do echo "thought $i" >> Journals/2026-11/11-18-2026.md; done
quiet; run; state

case_ "11. journal reaches 40 lines" "pushed — churn; journal now tracked"
for i in {7..40}; do echo "thought $i" >> Journals/2026-11/11-18-2026.md; done
quiet; run; state

case_ "12. edit to the now-TRACKED journal" "staged via add -u and counted as churn"
for i in {41..80}; do echo "thought $i" >> Journals/2026-11/11-18-2026.md; done
backdate 30
quiet; run; state

case_ "13. tomorrow's empty journal" "still excluded"
cp xTemplates/daily.md Journals/2026-11/11-19-2026.md
quiet; run; state

case_ "14. iCloud duplicate warning" "WARN naming 'visuals/img 2.png'"
# Stage ONLY the base image: `git add -A` here would also sweep in case 13's
# empty journal and make it look like the content gate let it through.
echo dup > visuals/img.png; git add visuals/img.png; git commit -q -m "base img"; git push -q origin main
cp visuals/img.png "visuals/img 2.png"
for i in {1..40}; do echo "l $i" >> Notes/trigger.md; done
quiet; run; state

case_ "15. dirty tree (plugins left uncommitted by design) + pull --rebase" "autoStash required; plain rebase would refuse"
for i in {1..5}; do echo "{\"x\":$i}" >> .obsidian/plugins/dataview/data.json; done
print -r -- "    dirty files: $(git status --porcelain | wc -l | tr -d ' ')"
git pull --rebase origin main >/dev/null 2>&1 \
  && print -r -- "    GOT   : plain pull --rebase OK (tree was clean — weak test)" \
  || print -r -- "    GOT   : plain pull --rebase REFUSED, as expected"
git -c rebase.autoStash=true pull --rebase origin main >/dev/null 2>&1 \
  && print -r -- "    GOT   : with autoStash OK" \
  || print -r -- "    GOT   : *** autoStash ALSO FAILED ***"

case_ "16. commit left unpushed by a failed push" "pushed 1 earlier unpushed commit(s), even with nothing new"
echo "orphan" > Notes/unpushed.md; git add Notes/unpushed.md; git commit -q -m "unpushed"
quiet; run
print -r -- "    GOT   : origin/main == HEAD? $( [[ $(git rev-parse origin/main) == $(git rev-parse HEAD) ]] && echo yes || echo NO )"

case_ "17. git commit fails (stand-in for gpg signing failure)" "COMMIT FAILED logged, no 'pushed', index reset"
mkdir -p .git/hooks; printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
for i in {1..40}; do echo "l $i" >> Notes/fail.md; done
quiet; run
print -r -- "    GOT   : staged after failure = $(git diff --cached --name-only | wc -l | tr -d ' ')  (want 0)"
mv .git/hooks/pre-commit .git/hooks/pre-commit.off

# Stand-in for the cloud routines: a second clone that pushes a journal.
remote_push_journal() {
  local p=$1
  rm -rf $ROOT/cloud; git clone -q $ROOT/origin.git $ROOT/cloud
  ( cd $ROOT/cloud && git config user.email c@d.e && git config user.name cloud \
    && mkdir -p ${p:h} && cp xTemplates/daily.md $p && echo "## Daily news brief" >> $p \
    && git add $p && git commit -q --no-gpg-sign -m "daily news brief" && git push -q origin main )
}

case_ "18. cloud brief pushes today's journal; local copy is an untouched template" "template replaced, no .local duplicate"
cp xTemplates/daily.md Journals/2026-11/11-20-2026.md
remote_push_journal Journals/2026-11/11-20-2026.md
quiet; run
print -r -- "    GOT   : .local files = $(ls Journals/2026-11 | grep -c local)  (want 0); brief in note = $(grep -c 'Daily news brief' Journals/2026-11/11-20-2026.md)"

case_ "19. same, but local copy has real writing" "moved aside keeping .md, incoming copy lands"
cp xTemplates/daily.md Journals/2026-11/11-21-2026.md; echo "my own words" >> Journals/2026-11/11-21-2026.md
remote_push_journal Journals/2026-11/11-21-2026.md
quiet; run
print -r -- "    GOT   : aside = $(ls Journals/2026-11 | grep local)"

print -r -- "=== 20. final state"
print -r -- "    commits: $(git rev-list --count HEAD)"
print -r -- "    pushed:  $(git rev-parse --short origin/main) == $(git rev-parse --short HEAD)"
print -r -- "    log:"
git log --format='      %s' | head -8
