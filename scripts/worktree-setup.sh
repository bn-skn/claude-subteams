#!/bin/bash
# worktree-setup.sh — prepare a LINKED git worktree for development, portably.
#
# Run this once right after `git worktree add` (or `claude --worktree <name>`) creates a
# new linked worktree. It never touches the main checkout's content — it only wires the
# new worktree up to share what's safe to share (node_modules) and clears what must never
# be shared across branches (stale build caches). It does NOT touch .env, store/, or any
# runtime DB — that's `.worktreeinclude`'s job (gitignored secrets) and the main
# checkout's job (live state), never a linked worktree's.
#
# Usage: worktree-setup.sh [--] [<path-to-worktree>]
#   <path-to-worktree>   defaults to the current directory. Resolved to the worktree's
#                         ROOT (via `git rev-parse --show-toplevel`) even if you point it
#                         at a subdirectory — the symlink and the build-cache cleanup both
#                         need to land at the root, not wherever you happened to be
#                         standing when you ran this. Must be a LINKED worktree — running
#                         this against the main checkout is refused (see below).
#   --                    end of options; whatever follows is the path even if it starts
#                         with '-'.
#
# Non-Node ecosystems (Rust/Python/Go): this script only NAMES their manifest files if
# present (Cargo.toml, requirements.txt, pyproject.toml, go.mod) — it never installs
# anything for them. It used to (a since-removed --full-setup flag): those install
# branches ran whichever pip/poetry/cargo/go happened to be first on PATH, no venv
# guarantee, and `pip install -e .` in particular can repoint a shared Python
# environment's package at this worktree — the same class of bug this whole script exists
# to prevent for Node, just in a different ecosystem. Install these yourself; they're
# cheap and not shared across worktrees the way node_modules is, so there's no correctness
# reason to automate it here.
#
# Why this exists (Node.js specifically): a project's node_modules can be large and
# contain native addons (e.g. better-sqlite3) built against one specific Node ABI
# (`process.versions.modules`). Re-running `npm install` per worktree means N full copies
# plus N native rebuilds — for a live-service repo, `npm install` from ANYWHERE other than
# the main checkout also risks mutating the one node_modules a running process depends on.
# The fix: every worktree SYMLINKS the main checkout's node_modules instead of installing
# its own, and only the main checkout ever runs `npm install`/`npm ci`.
#
# Exit codes: 0 success (including a no-op re-run or a non-fatal warning — this script
# reports problems loudly but does not abort on recoverable ones, so it's safe to call
# from an automated worktree-creation step); 1 usage/argument error; 2 target is not a
# linked worktree (see the main-checkout check below) or not inside a git working tree at
# all; 3 the target IS a linked worktree but setup couldn't complete — git repo state
# prevented determining the main worktree, or a filesystem operation (symlink creation)
# failed. 1/2 mean "you called this wrong or pointed it at the wrong directory"; 3 means
# "you called it right and it still didn't work — go read the warning above."

set -uo pipefail

# A caller with GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE exported (left over from a git hook,
# or from other scripting earlier in the same shell) silently redirects EVERY git command
# below at whatever repo those point to — `git -C <dir>` changes cwd before git runs, it
# does NOT override an already-exported GIT_DIR. Reproduced live: with GIT_DIR exported to
# the main checkout's .git, a real linked worktree got misdiagnosed as "the main checkout"
# (wrong diagnosis, though it still refused to run — this unset makes the diagnosis
# correct, not just the refusal safe).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

_die() { echo "[worktree-setup] $1" >&2; exit "${2:-1}"; }
_warn() { echo "[worktree-setup] WARNING: $*" >&2; }
_info() { echo "[worktree-setup] $*"; }

usage() {
  # Print the header comment above verbatim rather than a hardcoded line range: a fixed
  # `sed -n 'a,bp'` silently truncates the moment the header grows past line b (this
  # happened once already — the old range cut off before the exit-codes paragraph).
  # Print every leading comment/blank line, stop at the first real code line (`set -uo
  # pipefail`).
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} /^[[:space:]]*$/{print ""; next} {exit}' "$0"
}

# Resolve symlinks/relative bits to an absolute path.
# readlink -f is GNU-specific; older macOS/BSD readlink has no -f flag at all (unlike
# `cd`+`pwd -P`, which is POSIX-portable), so on that platform a perfectly valid symlink
# would resolve to empty and get misreported below as "<broken>". Prefer readlink -f when
# it's available (it also canonicalizes a path whose final component doesn't exist, which
# cd can't do) and fall back to cd+pwd -P — the two paths compared with this function are
# both known-existing here, so the fallback is exact for our actual use.
_realpath() {  # _realpath <path>
  readlink -f -- "$1" 2>/dev/null && return 0
  ( cd -- "$1" 2>/dev/null && pwd -P )
}

# ---- Argument parsing: one optional positional path, either before or after `--`. ----
TARGET=""
TARGET_GIVEN=0
END_OF_OPTS=0
for arg in "$@"; do
  if [ "$END_OF_OPTS" -eq 0 ]; then
    case "$arg" in
      --) END_OF_OPTS=1; continue ;;
      -h|--help) usage; exit 0 ;;
      -*) _die "unknown option '$arg' (usage: worktree-setup.sh [--] [<path>])" ;;
    esac
  fi
  [ "$TARGET_GIVEN" -eq 0 ] || _die "unexpected extra argument '$arg' (only one worktree path is accepted)"
  TARGET="$arg"
  TARGET_GIVEN=1
done
if [ "$TARGET_GIVEN" -eq 1 ]; then
  # An explicitly-passed empty string ("") is a caller bug, not "no argument" — falling
  # through to $PWD here would silently set up whatever directory happened to be current
  # instead of erroring, which is worse than just rejecting it.
  [ -n "$TARGET" ] || _die "worktree path must not be empty (pass no argument at all to default to \$PWD)"
else
  TARGET="$PWD"
fi

[ -d "$TARGET" ] || _die "no such directory: $TARGET"
TARGET=$(cd "$TARGET" 2>/dev/null && pwd -P) || _die "cannot resolve '$TARGET'"

command -v git >/dev/null 2>&1 || _die "git not found on PATH"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || _die "'$TARGET' is not inside a git working tree" 2

# Normalize to the worktree ROOT. Without this, running from a subdirectory (e.g.
# `cd <worktree>/src && worktree-setup.sh`) would symlink node_modules and sweep
# *.tsbuildinfo under src/ only — the root stays bare, tsc/vitest run from the root fail
# in a way that doesn't look like "forgot to run setup", and the build-cache cleanup
# becomes silently partial. Note: if $TARGET is an INITIALIZED submodule, --show-toplevel
# correctly resolves to the submodule's own root (it's its own repo) — that's intentional,
# not a bug, a submodule has its own package.json/node_modules if any.
TARGET=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null) \
  || _die "'$TARGET' is inside a git working tree but 'git rev-parse --show-toplevel' failed" 2
TARGET=$(cd "$TARGET" 2>/dev/null && pwd -P) || _die "cannot resolve worktree root '$TARGET'"

# Resolve `git rev-parse <flag>` (run with cwd=<dir>) to an ABSOLUTE, symlink-resolved
# path. The raw output can be relative to <dir> OR already absolute depending on git
# version/layout — cd'ing into it from within <dir> handles both cases uniformly, same
# trick coord.sh's _repokey uses for --git-common-dir. Do NOT string-concat <dir> with the
# raw output: that breaks the moment the output is already absolute.
_abs_git_path() {  # _abs_git_path <dir> <git-rev-parse-flag>
  local dir="$1" flag="$2" rel
  ( cd "$dir" 2>/dev/null || exit 1
    rel=$(git rev-parse "$flag" 2>/dev/null) || exit 1
    cd "$rel" 2>/dev/null || exit 1
    pwd -P
  )
}

# ---- Refuse to run against the main checkout. ----
# A linked worktree's --git-dir lives UNDER the main checkout's --git-common-dir (typically
# <common>/worktrees/<name>); the main checkout is the one case where --git-dir AND
# --git-common-dir resolve to the exact same path. This is the standard git-documented way
# to tell the two apart (see `git help worktree`), and it doesn't depend on any naming
# convention for the worktree directory itself.
GIT_DIR_ABS=$(_abs_git_path "$TARGET" --git-dir) || _die "git rev-parse --git-dir failed in '$TARGET'"
GIT_COMMON_DIR_ABS=$(_abs_git_path "$TARGET" --git-common-dir) || _die "git rev-parse --git-common-dir failed in '$TARGET'"

if [ "$GIT_DIR_ABS" = "$GIT_COMMON_DIR_ABS" ]; then
  _die "'$TARGET' is the MAIN checkout, not a linked worktree — nothing to set up here.
  This script prepares linked worktrees (created via 'git worktree add' or 'claude
  --worktree <name>') to share the main checkout's node_modules. The main checkout already
  has its own node_modules and is the ONLY place 'npm install'/'npm ci' should run." 2
fi

# ---- Find the main worktree. ----
# `git worktree list --porcelain` always lists the main worktree FIRST (git-documented
# behavior) — more robust than assuming the main worktree is literally
# dirname(git-common-dir), which happens to be true today but isn't part of git's
# documented contract the way worktree-list ordering is.
#
# Parsing it is trickier than it looks: `awk '{print $2}'` (the previous approach here)
# truncates at the first SPACE in the path. Reproduced live: main checkout at
# ".../sp2/dev repo" with a sibling ".../sp2/dev" present — awk silently returned the
# sibling, this script symlinked THAT project's node_modules, told the caller to run npm
# install there, and exited 0. That's the exact hazard this whole script exists to
# prevent, just aimed at the wrong directory.
#
# Fix: prefer `--porcelain -z` (NUL-terminated fields, git >= 2.36 — this host runs 2.53)
# piped through `tr '\0' '\n'`, which reconstructs the exact same line layout as the
# non-`-z` form but is immune to any special character in the path. If `-z` isn't
# supported, fall back to the plain form — `sed -n 's/^worktree //p'` is still correct
# there for embedded spaces/tabs (unlike awk, sed doesn't tokenize on whitespace); the one
# thing that fallback can't handle is a literal newline embedded in the path, which the
# -z form exists to cover and which worktree paths do not contain in practice.
_worktree_porcelain() {
  local out
  # IMPORTANT: convert NUL -> newline INSIDE the pipeline that feeds $(...), not after
  # capturing it. Bash command substitution reads its output through a plain string, which
  # cannot hold an embedded NUL byte — `out=$(git ... -z)` silently DROPS every NUL
  # ("ignored null byte in input") before `tr` ever runs on it, gluing every record's
  # fields together with nothing between them. Piping through `tr` first, while the data
  # is still a byte stream and not yet a shell string, avoids that entirely.
  out=$(cd "$TARGET" && git worktree list --porcelain -z 2>/dev/null | tr '\0' '\n')
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  ( cd "$TARGET" && git worktree list --porcelain 2>/dev/null )
}

WT_LIST=$(_worktree_porcelain)
[ -n "$WT_LIST" ] || _die "could not determine the main worktree via 'git worktree list --porcelain'" 3

# The main worktree's record is the first one, up to the first blank line (the record
# separator in both the -z-reconstructed and the plain form).
FIRST_RECORD=$(printf '%s\n' "$WT_LIST" | sed -n '1,/^$/p')
MAIN_WORKTREE_RAW=$(printf '%s\n' "$FIRST_RECORD" | sed -n 's/^worktree //p' | head -1)
[ -n "$MAIN_WORKTREE_RAW" ] && [ -d "$MAIN_WORKTREE_RAW" ] \
  || _die "could not determine the main worktree via 'git worktree list --porcelain'" 3

# Normalize with the SAME cd+pwd -P trick used for $TARGET above, so the equality check
# below compares two paths resolved identically (symlinks, trailing slashes, relative vs.
# absolute all collapsed the same way) instead of porcelain's raw string against a
# shell-resolved one.
MAIN_WORKTREE=$(cd "$MAIN_WORKTREE_RAW" 2>/dev/null && pwd -P) || _die "cannot resolve main worktree path '$MAIN_WORKTREE_RAW'" 3

# A bare repository's first porcelain record has no working tree at all — it has a
# "bare" attribute line instead of HEAD/branch. It's still "the main worktree" in git's
# terms, but there is no node_modules concept there; the Node section below skips it with
# an explicit message rather than telling the caller to `npm install` inside a bare repo.
MAIN_IS_BARE=0
printf '%s\n' "$FIRST_RECORD" | grep -q '^bare$' && MAIN_IS_BARE=1

# This should only be reachable if $TARGET slipped past the linked-worktree check above —
# e.g. a stray GIT_DIR/GIT_WORK_TREE pointed git at the wrong repo (the unset near the top
# of this script closes that specific hole, but this stays as defense in depth). It is a
# real, reachable check, not dead code: it was reproduced live before the unset was added.
[ "$MAIN_WORKTREE" != "$TARGET" ] \
  || _die "resolved main worktree equals target — check for stray GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE env vars in the calling shell" 2

_info "target worktree : $TARGET"
_info "main checkout   : $MAIN_WORKTREE"

# ==========================================================================
# Node.js: symlink node_modules from the main checkout, never install our own.
# ==========================================================================

MAIN_NM="$MAIN_WORKTREE/node_modules"
TARGET_NM="$TARGET/node_modules"

# ABI guard: process.versions.modules resolved AS IF you were sitting in each directory —
# a worktree may pin its own Node version via .nvmrc, so "which node runs here" can
# legitimately differ from the main checkout even though both use nvm. Sharing
# node_modules across a version mismatch would load native addons (better-sqlite3) built
# for the wrong ABI and fail at require()-time, not at setup-time — much worse to debug.
#
# Prints two lines: the ABI (or empty if it couldn't be determined), then the nvm-use
# status (ok|failed|na). "failed" specifically means a `.nvmrc` was present and `nvm use`
# could not switch to it — a KNOWN pinned-version mismatch, not a guessed one — and is
# handled separately below from "ABI just couldn't be determined at all".
_node_abi() {  # _node_abi <dir>
  (
    cd "$1" 2>/dev/null || { echo ""; echo "na"; exit 1; }
    local nvm_status="na"
    if [ -f .nvmrc ]; then
      local nvmdir="${NVM_DIR:-$HOME/.nvm}"
      if [ -s "$nvmdir/nvm.sh" ]; then
        # shellcheck disable=SC1091
        . "$nvmdir/nvm.sh" --no-use >/dev/null 2>&1
        if nvm use "$(cat .nvmrc)" >/dev/null 2>&1; then
          nvm_status="ok"
        else
          nvm_status="failed"
        fi
      fi
    fi
    local abi=""
    command -v node >/dev/null 2>&1 && abi=$(node -e 'console.log(process.versions.modules)' 2>/dev/null)
    echo "$abi"
    echo "$nvm_status"
  )
}

if [ "$MAIN_IS_BARE" -eq 1 ]; then
  _info "main checkout is a BARE repository (no working tree) — no node_modules concept there. Skipping Node setup."
elif [ -d "$MAIN_NM" ]; then
  MAIN_INFO=$(_node_abi "$MAIN_WORKTREE")
  MAIN_ABI=$(printf '%s\n' "$MAIN_INFO" | sed -n 1p)
  MAIN_NVM_STATUS=$(printf '%s\n' "$MAIN_INFO" | sed -n 2p)
  TARGET_INFO=$(_node_abi "$TARGET")
  TARGET_ABI=$(printf '%s\n' "$TARGET_INFO" | sed -n 1p)
  TARGET_NVM_STATUS=$(printf '%s\n' "$TARGET_INFO" | sed -n 2p)

  BLOCK_LINK=0
  if [ "$MAIN_NVM_STATUS" = "failed" ] || [ "$TARGET_NVM_STATUS" = "failed" ]; then
    # A `.nvmrc` requested a version `nvm use` couldn't switch to (not installed). Letting
    # this fall through silently (the old `|| true`) meant BOTH sides fell back to
    # whatever `node` happened to already be active, so they'd often report the SAME ABI
    # and the mismatch guard below would never fire — a no-op in exactly the scenario it
    # exists to catch. Treat it as a known mismatch on its own, before comparing ABIs.
    BLOCK_LINK=1
    _warn "a .nvmrc pins a Node version that 'nvm use' could not switch to (main checkout: \
$MAIN_NVM_STATUS, this worktree: $TARGET_NVM_STATUS) — a KNOWN pinned-version mismatch, \
not a guess. Refusing to symlink node_modules: run 'nvm install <version-in-.nvmrc>' \
first, or 'npm ci' inside this worktree to get its own isolated, correctly-built \
node_modules."
  elif [ -n "$MAIN_ABI" ] && [ -n "$TARGET_ABI" ] && [ "$MAIN_ABI" != "$TARGET_ABI" ]; then
    BLOCK_LINK=1
    _warn "Node ABI mismatch: this worktree resolves to process.versions.modules=$TARGET_ABI, \
the main checkout resolves to $MAIN_ABI. The shared node_modules contains native addons \
(e.g. better-sqlite3) built for the main checkout's ABI — they will NOT load under a \
different one. Do NOT symlink, and do NOT 'npm rebuild' the SHARED node_modules (that \
would break it for the main checkout / the live service). Instead run 'npm ci' inside \
THIS worktree to get its own isolated, correctly-built node_modules."
  elif [ -z "$MAIN_ABI" ] || [ -z "$TARGET_ABI" ]; then
    # Could not resolve an ABI on one or both sides for a reason OTHER than a failed
    # .nvmrc switch (no node on PATH at all, no nvm installed, etc). Warn but don't
    # block: if there's no working Node here, there's nothing that could load a
    # mismatched native addon in the first place, so refusing to link would only get in
    # the way with no safety benefit.
    _warn "could not determine Node ABI for comparison (main checkout: '${MAIN_ABI:-<unresolved>}', \
this worktree: '${TARGET_ABI:-<unresolved>}') — no working 'node' on PATH, or nvm not \
installed. Linking node_modules anyway; double-check manually once Node is set up here."
  fi

  if [ -L "$TARGET_NM" ]; then
    LINK_TARGET=$(_realpath "$TARGET_NM")
    MAIN_NM_REAL=$(_realpath "$MAIN_NM")
    if [ -n "$LINK_TARGET" ] && [ "$LINK_TARGET" = "$MAIN_NM_REAL" ]; then
      _info "node_modules: already symlinked to the main checkout — nothing to do."
    else
      _warn "node_modules is a symlink but points to '${LINK_TARGET:-<broken>}', not the \
main checkout's node_modules ('$MAIN_NM_REAL'). Leaving it alone — remove it yourself if \
this is stale."
    fi
  elif [ -e "$TARGET_NM" ]; then
    _warn "node_modules already exists in this worktree as a real directory (not a \
symlink) — leaving it untouched. If you want the shared symlink instead, remove it \
manually first: rm -rf '$TARGET_NM'"
  elif [ "$BLOCK_LINK" -eq 1 ]; then
    _info "node_modules: NOT linked (see warning above) — set up this worktree's own copy instead."
  else
    ln -s "$MAIN_NM" "$TARGET_NM" || _die "failed to symlink '$TARGET_NM' -> '$MAIN_NM'" 3
    _info "node_modules: symlinked -> $MAIN_NM"
    _warn "npm install/npm ci run from THIS worktree would mutate the SHARED node_modules \
that the main checkout (and any live service running from it) depends on. Only run \
'npm install'/'npm ci' from the main checkout: $MAIN_WORKTREE"
  fi
else
  _info "node_modules: main checkout has none — nothing to link."
fi

# ==========================================================================
# Build cache: *.tsbuildinfo is keyed to the source tree it was built from and goes stale
# the instant the branch differs — a worktree on its own branch that inherited one (e.g.
# copied instead of freshly checked out) would make tsc silently trust a wrong incremental
# state.
#
# node_modules and .git are PRUNED (not just filtered out of the results): once
# node_modules stops being a symlink (the ABI-mismatch path above tells the caller to run
# `npm ci` inside the worktree instead) a plain path filter would still walk its full
# ~960MB / hundreds of thousands of inodes on every single future run for no reason.
# `-prune` stops the descent instead of just hiding matches after the fact.
# ==========================================================================
STALE_CACHE=$(find "$TARGET" \( -name node_modules -o -name .git \) -prune -o -name '*.tsbuildinfo' -print 2>/dev/null)
if [ -n "$STALE_CACHE" ]; then
  REMOVED=""
  while IFS= read -r f; do
    if rm -f -- "$f" 2>/dev/null; then
      REMOVED="${REMOVED}${f}"$'\n'
    else
      # Reproduced live with a DIRECTORY named "*.tsbuildinfo": `rm -f` (no -r) fails on
      # it, writes to stderr, and — before this fix — got listed as "removed" anyway
      # because the report below was generated from the find output, not from what `rm`
      # actually did. Not using -r here on purpose: a directory matching this glob is
      # unexpected enough that silently recursing into it is a worse default than warning
      # and leaving it for a human to look at.
      _warn "could not remove stale build cache '$f' (directory instead of a file? permissions?) — leaving it, tsc may trust stale state."
    fi
  done < <(printf '%s\n' "$STALE_CACHE")
  if [ -n "$REMOVED" ]; then
    _info "removed stale build cache:"
    printf '%s' "$REMOVED" | sed 's/^/  - /'
  else
    _info "build cache: found candidates but none could be removed (see warnings above)."
  fi
else
  _info "build cache: no inherited *.tsbuildinfo found."
fi

# ==========================================================================
# Other ecosystems: informative only, nothing is installed here. There used to be a
# --full-setup flag that also ran cargo build / pip install / poetry install / go mod
# download. It was removed: with both requirements.txt and pyproject.toml present it ran
# `pip install -r` AND `poetry install` back to back into whatever interpreter happened to
# be first on PATH (no venv guarantee either way), and `pip install -e .` in particular can
# repoint a shared Python environment's package at this worktree — the same class of bug
# this whole script exists to prevent for Node, just in a different ecosystem. Unlike
# node_modules, these deps are cheap and NOT shared across worktrees, so there's no
# correctness reason to automate installing them here — do it yourself.
# ==========================================================================
_note_ecosystem() {  # _note_ecosystem <manifest-file> <label>
  [ -f "$TARGET/$1" ] && _info "$2 detected ($1) — install its dependencies yourself; not run automatically."
}
_note_ecosystem Cargo.toml       "Rust"
_note_ecosystem requirements.txt "Python (pip)"
_note_ecosystem pyproject.toml   "Python (poetry/pip)"
_note_ecosystem go.mod           "Go"

_info "done."
