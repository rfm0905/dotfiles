#!/bin/zsh
# Re-applies the subtask-fold patch to the Obsidian Todoist plugin whenever
# the installed main.js is stock (i.e. after a plugin update).
# Safe by construction: if anything fails, the stock plugin is left untouched.
set -euo pipefail

PLUGIN="$HOME/ObsidianNotes/.obsidian/plugins/todoist-sync-plugin"
HERE="$HOME/.local/share/todoist-plugin-patch"
PATCH="$HERE/subtask-fold.patch"
SRC="$HERE/src"
LOCK="$HERE/.lock"
MARKER="todoist-subtask-toggle"
REPO="https://github.com/jamiebrynes7/obsidian-todoist-plugin.git"

log()    { print -r -- "$(date '+%F %T') $*"; }
notify() { osascript -e "display notification \"$1\" with title \"Todoist plugin patch\"" >/dev/null 2>&1 || true; }

[[ -f "$PLUGIN/main.js" ]] || { log "plugin not installed, nothing to do"; exit 0; }
grep -q "$MARKER" "$PLUGIN/main.js" && { log "already patched"; exit 0; }

# give Obsidian time to finish writing an update before we read it
[[ "${1:-}" == "--now" ]] || sleep 15
grep -q "$MARKER" "$PLUGIN/main.js" && { log "already patched"; exit 0; }

mkdir "$LOCK" 2>/dev/null || { log "another run in progress"; exit 0; }
# on exit (success or failure): drop build deps/output (~500 MB) so only the
# git checkout stays on disk; the next rebuild reinstalls from npm's cache
cleanup() { [[ -d "$SRC/.git" ]] && git -C "$SRC" clean -qfdx; rmdir "$LOCK" 2>/dev/null; }
trap cleanup EXIT

# Snapshot the stock file NOW, while it is known to be stock. iCloud can swap
# main.js for a patched copy from another device during the ~15s build, and
# copying it at the end once wrote a PATCHED file into backups/*.stock.
STOCK_SNAP="$HERE/.stock-snapshot.js"
cp "$PLUGIN/main.js" "$STOCK_SNAP"
grep -q "$MARKER" "$STOCK_SNAP" && { rm -f "$STOCK_SNAP"; log "already patched (iCloud swapped it in)"; exit 0; }

VERSION=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN/manifest.json")
log "stock v$VERSION detected, patching"

[[ -d "$SRC/.git" ]] || git clone -q "$REPO" "$SRC"
git -C "$SRC" fetch -q --tags --force origin
if ! git -C "$SRC" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  log "no upstream tag $VERSION"; notify "No source tag for v$VERSION, stock plugin left alone"; exit 1
fi
git -C "$SRC" checkout -q --force "refs/tags/$VERSION"   # also discards last run's patch
if ! git -C "$SRC" apply --check "$PATCH" 2>/dev/null; then
  log "patch no longer applies to v$VERSION"; notify "Patch doesn't apply to v$VERSION, stock plugin left alone"; exit 1
fi
git -C "$SRC" apply "$PATCH"

cd "$SRC"
npm ci --ignore-scripts --include=dev --no-audit --no-fund --loglevel=error
(cd plugin && npx vite build --logLevel warn)

BUILT="$SRC/plugin/dist/main.js"
[[ -f "$BUILT" ]] && grep -q "$MARKER" "$BUILT" || { log "build output missing or unpatched"; notify "Build failed for v$VERSION, stock plugin left alone"; exit 1; }

mkdir -p "$HERE/backups"
mv "$STOCK_SNAP" "$HERE/backups/main.js.$VERSION.stock"
cp "$BUILT" "$PLUGIN/main.js.tmp" && mv "$PLUGIN/main.js.tmp" "$PLUGIN/main.js"
log "installed patched v$VERSION (stock backup in $HERE/backups)"
notify "Patched v$VERSION. Reload Obsidian to pick it up."
