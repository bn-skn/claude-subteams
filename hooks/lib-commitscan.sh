#!/bin/bash
# shellcheck disable=SC2034  # CS_* are the library interface, read by the sourcing hook
# lib-commitscan.sh — statement-level view of a Bash command line for the TEST gate
# (sourced by hooks/pre-commit-gate AFTER hooks/lib-gitcmd.sh: it reuses its
# tokenizer _gc_tokenize and _gc_is_assign; never executed, no side effects).
#
# lib-gitcmd.sh lists git invocations only. The test gate (IMPL-PLAN testing-ui
# §5.4, review fixes B13-B17) must also know what ELSE the line runs before a
# commit (`seq 1 200 > a.js && git commit -am x`), where each statement runs (cd /
# git -C, with simple VAR=literal assignments resolved), which environment it
# gets (VAR= prefixes, env, export, GIT_DIR & co.) and where output is redirected.
#
# cs_scan "<command line>" fills, one slot per FLATTENED statement in execution
# order (`bash -c "…"`, `eval …` and `coord.sh commit-lock -- …` are expanded in
# place, depth-capped):
#   CS_KIND[i]  assign | export | cd | noop | echo | git | st | other
#               (echo = echo/printf/cat; st = subteams-tests / discover-tests.sh)
#   CS_TXT[i]   the statement as text (first 100 chars, for messages)
#   CS_SUB[i]   git subcommand ("" for non-git)
#   CS_ARGS[i]  git: arguments after the subcommand, $'\037'-joined, redirections
#               removed; st: all arguments
#   CS_DIR[i]   absolute directory the statement runs in (cd state + git -C);
#               "" = unresolvable (a $VAR / $(…) / `cd -` we cannot know)
#   CS_DRAW[i]  the raw dir/cd word that made it unresolvable (for messages)
#   CS_ENV[i]   1 = a VAR=value prefix or an `env` wrapper changes its environment
#   CS_GENV[i]  1 = GIT_INDEX_FILE / GIT_DIR / GIT_WORK_TREE / GIT_OBJECT_DIRECTORY /
#               GIT_COMMON_DIR set for it (prefix, env, or any earlier assignment /
#               export in the line), or git --git-dir / --work-tree / -c core.worktree
#   CS_PEXP[i]  1 = an export / declare / set / source / . ran earlier in the line
#   CS_REDIR[i] output redirection targets, $'\037'-joined: absolute paths, "&N"
#               / /dev/* kept as is, "?" = unresolvable
#   CS_X[i]     1 = behind xargs (arguments come from stdin)
#   CS_RUN[i]   st: 1 = the word `run` is among its arguments
#   CS_GOPT[i]  git: 1 = global -c / --config-env / --exec-path options (a "read-
#               only" git command with them can run anything: diff.external …)
#   CS_RELIABLE 0 = the tokenizer was unsure (open quote, awk died, depth cap) —
#               the arrays may be incomplete
# Literal assignments seen so far are kept in CS_VN[] / CS_VV[] (bash 3.2: no
# associative arrays). Known limits (accepted, see the gate header): subshell
# scopes `( cd x )` are flattened (a cd inside parentheses is taken as leaking);
# `cd a || cd b` is read as both cds in sequence (|| / && are not modelled);
# aliases and functions are invisible.
# Unresolvable commit targets (decision R6, coordinator 13.11.2026): an unknown
# $VAR / other $(…) / `cd -` / popd / `env -C` falls back to the CWD repository —
# deny "use a literal path" only when that repo has an active contract, else allow
# with a warning. RESIDUAL: from a cwd WITHOUT a contract, an unresolvable target
# that really points into a contracted repository escapes the test gate (warning
# only). The same R6 rule decides commits into different repos in one line: deny
# only if one of the resolved target repos has a contract.

# (GIT_*_PATHSPECS change how a replayed pathspec matches: not replayed, so denied)
CS_GITVARS='GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_ICASE_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_LITERAL_PATHSPECS'

cs__reset() {
  CS_KIND=(); CS_TXT=(); CS_SUB=(); CS_ARGS=(); CS_DIR=(); CS_DRAW=(); CS_ENV=(); CS_GENV=()
  CS_PEXP=(); CS_REDIR=(); CS_X=(); CS_RUN=(); CS_GOPT=(); CS_SEP=(); CS_DEPTH=(); CS_CFG=(); CS_LITPS=(); CS_KW=(); CS_UGLOB=(); CS_QCMD=(); CS_ENVS=(); CS_ACOMMIT=(); CS_VWRAP=()
  CS_VN=(); CS_VV=(); CS_RELIABLE=1; CS_CUR="$PWD"; CS_CURRAW=""; CS_LGENV=0; CS_LEXP=0; CS_LCFG=0
  CS_SHAPE=""
}

cs__isgitvar() { case " $CS_GITVARS " in *" $1 "*) return 0 ;; esac; return 1; }
# variables that inject configuration or other binaries into git: GIT_CONFIG_COUNT /
# _KEY_n / _VALUE_n / _PARAMETERS / _GLOBAL / _SYSTEM, GIT_EXEC_PATH, PATH, and
# HOME / XDG_CONFIG_HOME (they move the global git config)
cs__iscfgvar() { case "$1" in GIT_CONFIG*|GIT_EXEC_PATH|PATH|HOME|XDG_CONFIG_HOME) return 0 ;; esac; return 1; }
# `git -c` keys a commit line may carry under a contract (cosmetic / identity only)
cs__cfg_ok() {
  case "$(printf '%s' "${1%%=*}" | tr '[:upper:]' '[:lower:]')" in
    user.name|user.email|commit.gpgsign|core.quotepath|color.*) return 0 ;;
  esac
  return 1
}

cs__setvar() { # <name> <value|""> <literal 0/1> — record (or forget) a literal value
  local k
  for k in ${CS_VN[@]+"${!CS_VN[@]}"}; do
    if [ "${CS_VN[k]}" = "$1" ]; then
      if [ "$3" = 1 ]; then CS_VV[k]="$2"; else unset 'CS_VN[k]' 'CS_VV[k]'; fi
      return 0
    fi
  done
  [ "$3" = 1 ] || return 0
  k=${#CS_VN[@]}; while [ -n "${CS_VN[k]+x}" ]; do k=$((k+1)); done
  CS_VN[k]="$1"; CS_VV[k]="$2"
}

cs__getvar() { # <name> -> CS_GV; rc 1 unknown (HOME comes from the hook's environment)
  local k
  for k in ${CS_VN[@]+"${!CS_VN[@]}"}; do [ "${CS_VN[k]}" = "$1" ] && { CS_GV="${CS_VV[k]}"; return 0; }; done
  [ "$1" = HOME ] && [ -n "${HOME:-}" ] && { CS_GV="$HOME"; return 0; }
  return 1
}

# cs_expand <word> -> CS_E; rc 1 = unresolvable (unknown $VAR, $(…), backtick).
# Resolves ~, ~/…, $NAME and ${NAME} from literal assignments earlier in the line.
# `$(git rev-parse --show-toplevel)` (or the backtick form) at the start of a word
# is resolved too: it is literally the toplevel of the directory at that point.
CS_TOPSUB1='$(git rev-parse --show-toplevel)'
CS_TOPSUB2='`git rev-parse --show-toplevel`'
cs_expand() {
  local w="$1" out="" re='^([^$`]*)\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))(.*)$' top
  case "$w" in '~') w="${HOME:-}" ;; '~/'*) w="${HOME:-}/${w#\~/}" ;; esac
  case "$w" in
    "$CS_TOPSUB1"*|"$CS_TOPSUB2"*)
      [ -n "$CS_CUR" ] && top=$(git -C "$CS_CUR" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || return 1
      case "$w" in "$CS_TOPSUB1"*) w="${w#"$CS_TOPSUB1"}" ;; *) w="${w#"$CS_TOPSUB2"}" ;; esac
      out="$top" ;;
  esac
  case "$w" in *'`'*) return 1 ;; esac
  while :; do
    case "$w" in *'$'*) ;; *) CS_E="$out$w"; return 0 ;; esac
    [[ $w =~ $re ]] || return 1
    cs__getvar "${BASH_REMATCH[3]:-${BASH_REMATCH[4]}}" || return 1
    out="$out${BASH_REMATCH[1]}$CS_GV"; w="${BASH_REMATCH[5]}"
  done
}

cs__abs() { # <base dir|""> <path> -> CS_P absolute (lexical join); rc 1 if base unknown and path relative
  case "$2" in
    /*) CS_P="$2" ;;
    *) [ -n "$1" ] || return 1; CS_P="${1%/}/$2" ;;
  esac
  return 0
}

cs__canon_dir() { # <dir> -> canonical path on stdout (dir must exist)
  (cd -P -- "$1" 2>/dev/null && pwd)
}

# cs__redir <token> <next token> <loose 0/1> -> CS_RT target ("" = not a redirection),
# CS_RSKIP 1 when the target was the next token. loose=1 (echo/printf/cat): a '>'
# anywhere in the token counts (`echo x>a.js` is one token).
cs__redir() {
  local t="$1" r
  CS_RT=""; CS_RSKIP=0
  r="${t#"${t%%[!0-9&]*}"}"            # drop a leading fd number / &
  case "$r" in
    '>'*)
      r="${r#>}"; r="${r#>}"; r="${r#|}"
      case "$r" in                   # >&N / >&- duplicate a descriptor; >&file (or ">& file") is a file
        '&') case "$2" in ''|*[!0-9-]*) CS_RT="$2"; CS_RSKIP=1; [ -n "$CS_RT" ] || CS_RT="?"; return 0 ;; *) return 0 ;; esac ;;
        '&'*) case "${r#&}" in *[!0-9-]*) r="${r#&}" ;; *) return 0 ;; esac ;;
      esac ;;
    *)
      [ "$3" = 1 ] || return 0
      case "$t" in *'>'*) r="${t##*>}" ;; *) return 0 ;; esac ;;
  esac
  if [ -z "$r" ]; then CS_RT="$2"; CS_RSKIP=1; else CS_RT="$r"; fi
  [ -n "$CS_RT" ] || CS_RT="?"
}

cs__resolve_target() { # <raw target> -> CS_RT2 (absolute | &N | /dev/* | ?)
  case "$1" in
    '&'*|/dev/*) CS_RT2="$1"; return 0 ;;
  esac
  if cs_expand "$1" && cs__abs "$CS_CUR" "$CS_E"; then CS_RT2="$CS_P"; else CS_RT2="?"; fi
}

# ---------------------------------------------------------------- shape view
# cs__msg_prepass: replaces every WELL-FORMED commit-message heredoc
#   $(cat <<'EOF' … EOF)   (also `$(cat<<`, `<<-`, "EOF", or an unquoted delimiter
#   whose body has no `$` and no backtick)
# — delimiter, end of line, body, a line equal to the delimiter, then only blanks
# and `)` — by the word SUBTEAMS_MSG, so quotes / apostrophes / backticks / `$(`
# text inside the message can neither split nor fool the tokenizers. Anything else
# stays as it is and is judged by cs__tokenize (a stray `$(` = substitution).
cs__msg_prepass() {
  LC_ALL=C awk 'BEGIN { RS = "\001" } { s = s $0 } END {
    out = ""
    while ((i = index(s, "$(cat")) > 0) {
      out = out substr(s, 1, i - 1); rest = substr(s, i + 5); ok = 0
      if (match(rest, /^[ \t]*<</)) {
        r = substr(rest, RLENGTH + 1); dash = 0
        if (substr(r, 1, 1) == "-") { dash = 1; r = substr(r, 2) }
        sub(/^[ \t]*/, "", r); q = substr(r, 1, 1); w = ""; quoted = 0
        if (q == "\047" || q == "\"") {
          r = substr(r, 2); e = index(r, q)
          if (e) { w = substr(r, 1, e - 1); r = substr(r, e + 1); quoted = 1 }
        } else if (match(r, /^[A-Za-z0-9_.-]+/)) { w = substr(r, 1, RLENGTH); r = substr(r, RLENGTH + 1) }
        if (w != "" && match(r, /^[ \t]*\n/)) {
          r = substr(r, RLENGTH + 1); found = 0; body = ""
          while (length(r) > 0) {
            e = index(r, "\n")
            if (e) { line = substr(r, 1, e - 1); r = substr(r, e + 1) } else { line = r; r = "" }
            l2 = line; if (dash) sub(/^\t+/, "", l2)
            if (l2 == w) { found = 1; break }
            body = body line "\n"
          }
          if (found && match(r, /^[ \t\n]*\)/) && (quoted || (index(body, "$") == 0 && index(body, "`") == 0))) {
            ok = 1; s = substr(r, RLENGTH + 1); out = out "SUBTEAMS_MSG"
          }
        }
      }
      if (!ok) { out = out "$(cat"; s = rest }
    }
    printf "%s", out s }'
}

# cs__tokenize — a COPY of lib-gitcmd.sh _gc_tokenize (that one is the review
# gate's, unchanged since 1.49) extended for the contract SHAPE check: each
# statement line is "<sep>\035<tokens \037-joined>" where <sep> is what ended it
# (n newline, ; , A &&, O ||, | pipe, & background, ( ) ` subshell/substitution,
# E end of input); constructs the shape forbids are reported as "\034<reason>"
# lines (quote-aware: nothing inside '…' or $'…' or a QUOTED heredoc body counts):
# $( / backticks outside single quotes (except the exact toplevel lookup
# `$(git rev-parse --show-toplevel)` / its backtick form), <( >( process
# substitution, ( ) subshells, ||, & background, <> , <<< here-strings, and an
# UNQUOTED heredoc body containing $ or a backtick. Last line: "\036OK"|"\036BAD".
cs__tokenize() {
  LC_ALL=C awk -v E1='$(git rev-parse --show-toplevel)' -v E2='`git rev-parse --show-toplevel`' '
    function flush() { if (has) { out = out (nt++ ? US : "") tok } tok = ""; has = 0 }
    function emit(sep) {
      flush()
      if (nt) { if (held != "") print hsep GS held; held = out; hsep = sep }
      else if (held != "" && (hsep == "n" || hsep == ";")) hsep = sep
      out = ""; nt = 0
    }
    function flag(r) { if (!(r in seen)) { seen[r] = 1; print FL r } }
    # quoted / escaped > * ? [ are marked (\001-\004) so later checks can tell
    # `echo "a -> b"` from a redirection and "src/[id]" from a shell glob
    # \005 (in a token): the word was quoted / escaped / ANSI-C somewhere — so a
    # COMMAND word built that way ("g"it, g\it, $'\x67it') is visible as such
    function mk(c) { return c == ">" ? "\001" : c == "*" ? "\002" : c == "?" ? "\003" : c == "[" ? "\004" : c }
    BEGIN { RS = "\001"; US = "\037"; GS = "\035"; FL = "\034"; s = ""; q = ""; tok = ""; has = 0; out = ""; nt = 0; nh = 0; ar = 0; bad = 0; held = ""; hsep = "" }
    { s = s $0 }
    END {
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == "\047") { if (c == "\047") q = ""; else tok = tok (c == "\n" ? " " : mk(c)); continue }
        if (q == "A") {
          if (c == "\\") { tok = tok mk(substr(s, i + 1, 1)); i++ }
          else if (c == "\047") q = ""
          else tok = tok (c == "\n" ? " " : mk(c))
          continue
        }
        if (q == "\"") {
          if (c == "\\") {
            nx = substr(s, i + 1, 1)
            if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { tok = tok nx; i++ } else tok = tok c
            continue
          }
          if (c == "$" && substr(s, i + 1, 1) == "(") {
            if (substr(s, i, length(E1)) == E1) { tok = tok E1; i += length(E1) - 1; continue }
            flag("command substitution $( ) inside double quotes")
          }
          if (c == "`") {
            if (substr(s, i, length(E2)) == E2) { tok = tok E2; i += length(E2) - 1; continue }
            flag("command substitution with backticks")
          }
          if (c == "\"") q = ""; else tok = tok (c == "\n" ? " " : mk(c))
          continue
        }
        if (c == "\\") {
          nx = substr(s, i + 1, 1); i++
          if (nx != "\n") { tok = tok "\005" mk(nx); has = 1 }
          continue
        }
        if (c == "$" && substr(s, i + 1, 1) == "\047") { q = "A"; tok = tok "\005"; has = 1; i++; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(") {
          if (substr(s, i, length(E1)) == E1) { tok = tok E1; has = 1; i += length(E1) - 1; continue }
          flag("command substitution $( )")
        }
        if (c == "`" && substr(s, i, length(E2)) == E2) { tok = tok E2; has = 1; i += length(E2) - 1; continue }
        if (c == "\047" || c == "\"") { q = c; tok = tok "\005"; has = 1; continue }
        if (c == " " || c == "\t") { flush(); continue }
        if (c == "#" && !has) { while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
        if (c == "<" && substr(s, i + 1, 1) == ">") flag("<> read-write redirection")
        if (ar == 0 && c == "<" && substr(s, i + 1, 2) == "<<") flag("here-string <<<")
        if (ar == 0 && c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") {
          j = i + 2; dash = 0
          if (substr(s, j, 1) == "-") { dash = 1; j++ }
          while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
          w = ""; qc = substr(s, j, 1); hq = 0
          if (qc == "\047" || qc == "\"") {
            hq = 1; j++
            while (j <= n && substr(s, j, 1) != qc) { w = w substr(s, j, 1); j++ }
            j++
          } else {
            while (j <= n && substr(s, j, 1) !~ /[ \t\n;|&()<>]/) { w = w substr(s, j, 1); j++ }
          }
          if (w ~ /[\\\047"]/) hq = 1
          gsub(/\\/, "", w)
          if (w != "") { hw[nh] = w; hd[nh] = dash; hqq[nh] = hq; nh++ }
          tok = tok "<<" w; has = 1; i = j - 1
          continue
        }
        if (c == "(") {
          if (ar > 0 || substr(s, i - 1, 1) == "(") ar += (ar > 0 ? 1 : 2)
          pv = substr(s, i - 1, 1)
          if (pv == "<" || pv == ">") flag("process substitution <( ) / >( )")
          else if (pv != "$") flag("subshell or grouping ( )")
        }
        else if (c == ")" && ar > 0) ar--
        if (c == "`") flag("command substitution with backticks")
        if (c == "|" && substr(s, i - 1, 1) == ">") { tok = tok c; has = 1; continue }   # >| clobber redirection, not a pipe
        if (c == "\n" || c == ";" || c == "|" || c == "(" || c == ")" || c == "`") {
          sep = (c == "\n" ? "n" : c)
          if (c == "|" && substr(s, i + 1, 1) == "|") { sep = "O"; i++; flag("|| (or-list)") }
          else if (c == "|" && substr(s, i + 1, 1) == "&") i++
          emit(sep)
          if (c == "\n" && nh > 0) {
            for (h = 0; h < nh; h++) {
              found = 0
              while (i < n) {
                e = index(substr(s, i + 1), "\n")
                if (e == 0) { line = substr(s, i + 1); i = n } else { line = substr(s, i + 1, e - 1); i = i + e }
                if (hd[h]) sub(/^\t+/, "", line)
                if (line == hw[h]) { found = 1; break }
                if (!hqq[h] && (index(line, "$") || index(line, "`"))) flag("unquoted heredoc body with $ or a backtick")
              }
              if (!found) bad = 1
            }
            nh = 0
          }
          continue
        }
        if (c == "&") {
          pv = substr(s, i - 1, 1); nx = substr(s, i + 1, 1)
          if (pv == ">" || pv == "<" || nx == ">") { tok = tok c; has = 1; continue }
          if (nx == "&") { i++; emit("A"); continue }
          flag("& (background job)"); emit("&")
          continue
        }
        tok = tok c; has = 1
      }
      emit("E")
      if (held != "") print hsep GS held
      print (q == "" && !bad ? "\036OK" : "\036BAD")
    }'
}

cs__envdir() { # <env -C value> — resolved like a cd (so the TARGET is right), "" when unknown
  CS_R_DIRSET=1
  if cs_expand "$1" && cs__abs "$CS_CUR" "$CS_E" && [ -d "$CS_P" ]; then CS_R_DIR=$(cs__canon_dir "$CS_P"); CS_R_DRAW=""
  else CS_R_DIR=""; CS_R_DRAW="env -C $1"; fi
}

cs__record() { # <kind> <tokens from index i…> uses locals of cs__stmt via dynamic scope
  local k=${#CS_KIND[@]} txt
  txt="${CS_STMT_TXT:0:100}"
  CS_KIND[k]="$1"; CS_TXT[k]="$txt"; CS_SUB[k]="${CS_R_SUB:-}"; CS_ARGS[k]="${CS_R_ARGS:-}"
  if [ "$CS_R_DIRSET" = 1 ]; then CS_DIR[k]="$CS_R_DIR"; CS_DRAW[k]="$CS_R_DRAW"; else CS_DIR[k]="$CS_CUR"; CS_DRAW[k]="$CS_CURRAW"; fi
  CS_ENV[k]="$CS_R_ENV"; CS_GENV[k]="$CS_R_GENV"; CS_PEXP[k]="$CS_LEXP"
  CS_REDIR[k]="$CS_R_REDIR"; CS_X[k]="$CS_R_X"; CS_RUN[k]="${CS_R_RUN:-0}"
  CS_GOPT[k]="${CS_R_GOPT:-0}"; CS_SEP[k]="${CS_STMT_SEP:-n}"; CS_DEPTH[k]="${CS_STMT_DEPTH:-0}"
  CS_CFG[k]="$CS_R_CFG"; CS_LITPS[k]="${CS_R_LITPS:-0}"; CS_KW[k]="${CS_R_KW:-0}"; CS_UGLOB[k]="${CS_R_UGLOB:-0}"
  CS_QCMD[k]="${CS_R_QCMD:-0}"; CS_ENVS[k]="${CS_R_ENVS:-0}"; CS_ACOMMIT[k]="${CS_R_ACOMMIT:-0}"
  CS_VWRAP[k]="${CS_R_VWRAP:-0}"
}

# cs__argcommit <first index> (uses T / n of cs__stmt) -> CS_R_ACOMMIT=1 when the
# WORDS `git [global options] commit` sit among the arguments of a statement that is
# not itself modelled as a git command: `./wrap.sh git commit`, `find -exec git
# commit`, `watch git commit`, `$UNKNOWN commit-lock -- git commit`. Word by word: a
# quoted multi-word string (echo "… && git commit", gh --body '…', ssh host '…') is
# ONE argument and never equals `git` — prose stays ignored (round 5, items 1 and 9);
# separately quoted words ("git" "commit") still reach a wrapper as git + commit.
cs__argcommit() {
  local p q
  CS_R_ACOMMIT=0
  p="$1"
  while [ "$p" -lt "$n" ]; do
    if [ "${T[$p]##*/}" = git ]; then
      q=$((p + 1))
      while [ "$q" -lt "$n" ]; do
        case "${T[$q]}" in
          -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) q=$((q + 2)) ;;
          -*) q=$((q + 1)) ;;
          *) break ;;
        esac
      done
      if [ "$q" -lt "$n" ] && [ "${T[$q]}" = commit ]; then CS_R_ACOMMIT=1; return 0; fi
    fi
    p=$((p + 1))
  done
  return 1
}

# cs_scan "<command line>" [depth] [inherited env 0/1] [inherited git env 0/1]
# Also fills CS_SEP[i] (what ended the statement, see cs__tokenize), CS_DEPTH[i]
# (0 = top level, >0 = inside bash -c / eval), CS_CFG[i] (the first config / PATH
# injection on it: a `git -c` key outside the allowlist, --config-env, GIT_CONFIG_*,
# GIT_EXEC_PATH or PATH set for it or earlier in the line), CS_LITPS[i] (git
# --literal-pathspecs) and CS_SHAPE (newline-separated forbidden constructs).
cs_scan() {
  local depth="${2:-0}" pe="${3:-0}" pg="${4:-0}" line sentinel=0 txt
  local -a T
  if [ "$depth" -eq 0 ]; then cs__reset; txt=$(printf '%s' "$1" | cs__msg_prepass); else txt="$1"; fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      $'\036OK') sentinel=1; continue ;;
      $'\036BAD') continue ;;
      $'\034'*) CS_SHAPE="$CS_SHAPE${CS_SHAPE:+$'\n'}${line#?}"; continue ;;
    esac
    CS_STMT_SEP="${line%%$'\035'*}"; CS_STMT_DEPTH="$depth"
    IFS=$'\037' read -r -a T <<< "${line#*$'\035'}"
    cs__stmt "$depth" "$pe" "$pg"
  done < <(printf '%s' "$txt" | cs__tokenize)
  [ "$sentinel" -eq 1 ] || CS_RELIABLE=0
}

cs__stmt() { # uses T from cs_scan
  local depth="$1" n=${#T[@]} i=0 w base wrap="" need_pos=0 j k v nm assigns=0 dir d raw
  local CS_R_ENV="$2" CS_R_GENV="$3" CS_R_X=0 CS_R_REDIR="" CS_R_SUB="" CS_R_ARGS="" CS_R_RUN=0 CS_STMT_TXT
  local CS_R_GOPT=0 CS_R_CFG="" CS_R_LITPS=0 CS_R_KW=0 CS_R_UGLOB=0 PRE_REDIR=0 CS_R_QCMD=0 CS_R_ENVS=0 CS_R_ACOMMIT=0 CS_R_VWRAP=0 CS_R_VVAL=""
  local CS_R_DIR="" CS_R_DRAW="" CS_R_DIRSET=0
  local -a TM
  [ "$CS_LGENV" = 1 ] && CS_R_GENV=1
  [ "$CS_LCFG" != 0 ] && CS_R_CFG="$CS_LCFG"
  # TM keeps the quote markers of cs__tokenize (redirections, shell globs); T is the
  # plain text every other use sees
  TM=("${T[@]}")
  T=("${T[@]//$'\001'/>}"); T=("${T[@]//$'\002'/*}"); T=("${T[@]//$'\003'/?}"); T=("${T[@]//$'\004'/[}"); T=("${T[@]//$'\005'/}")
  CS_STMT_TXT=$(printf '%s ' "${T[@]}" | tr -d '\000-\037'); CS_STMT_TXT="${CS_STMT_TXT% }"
  while :; do
    while [ "$i" -lt "$n" ]; do
      w="${T[$i]}"
      case "$w" in
        '!'|if|then|else|elif|do|while|until|'{'|time|exec|nohup|builtin|command|sudo|doas|nice|ionice|stdbuf|setsid|timeout|flock|xargs)
          wrap="$w"; i=$((i + 1))
          case "$w" in '!'|if|then|else|elif|do|while|until|'{') CS_R_KW=1 ;; esac
          case "$w" in timeout|flock) need_pos=1 ;; *) need_pos=0 ;; esac
          [ "$w" = xargs ] && CS_R_X=1
          continue ;;
        env) wrap=env; CS_R_ENV=1; i=$((i + 1)); continue ;;
        -*)
          if [ -n "$wrap" ]; then
            case "$wrap:$w" in
              env:-C|env:--chdir) cs__envdir "${T[$((i + 1))]:-}"; CS_R_CFG="${CS_R_CFG:-env $w}"; i=$((i + 2)) ;;
              env:-u|env:--unset) i=$((i + 2)) ;;
              env:--unset=*) i=$((i + 1)) ;;
              env:--chdir=*) cs__envdir "${w#--chdir=}"; CS_R_CFG="${CS_R_CFG:-env --chdir}"; i=$((i + 1)) ;;
              env:-S|env:--split-string) CS_R_CFG="${CS_R_CFG:-env $w}"; CS_R_ENVS=1; i=$((i + 2)) ;;
              env:-S?*|env:--split-string=*) CS_R_CFG="${CS_R_CFG:-env $w}"; CS_R_ENVS=1; i=$((i + 1)) ;;
              env:*) CS_R_CFG="${CS_R_CFG:-env $w}"; i=$((i + 1)) ;;   # (-S… handled above)   # -S…, -i, -0, --split-string=… : only NAME=value and -u pass
              sudo:-u|sudo:-g|sudo:-h|sudo:-C|sudo:-p|sudo:-r|sudo:-t|sudo:-U|doas:-u|doas:-C|nice:-n|ionice:-c|ionice:-n|ionice:-p|ionice:-P|ionice:-t|timeout:-s|timeout:-k|stdbuf:-i|stdbuf:-o|stdbuf:-e|flock:-w|flock:-E|xargs:-I|xargs:-n|xargs:-P|xargs:-L|xargs:-d|xargs:-E|xargs:-s|xargs:-a)
                i=$((i + 2)) ;;
              *) i=$((i + 1)) ;;
            esac
            continue
          fi
          break ;;
      esac
      if [ "$need_pos" -eq 1 ] && [ -n "$wrap" ]; then need_pos=0; i=$((i + 1)); continue; fi
      # a redirection BEFORE the command word (`>f git commit`, `2>f git …`): skip it
      # here; the redirect scan below sees every token of the statement
      case "${TM[$i]}" in
        [0-9]'>'*|[0-9][0-9]'>'*|'>'*|'&>'*|[0-9]'<'*|'<'*)
          case "${TM[$i]}" in *'>'|*'<'|'&>'|'>>'|*'>|') i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
          PRE_REDIR=1; continue ;;
      esac
      if _gc_is_assign "$w"; then
        nm="${w%%=*}"; assigns=$((assigns + 1))
        cs__isgitvar "$nm" && CS_R_GENV=1
        cs__iscfgvar "$nm" && CS_R_CFG="${CS_R_CFG:-$nm=}"
        CS_R_ENV=1; i=$((i + 1)); continue
      fi
      break
    done
    if [ "$i" -ge "$n" ]; then
      if [ "$assigns" -gt 0 ] && [ -z "$wrap" ]; then
        # a plain assignment statement: remember literal values for later $VAR
        for k in "${T[@]}"; do
          _gc_is_assign "$k" || continue
          nm="${k%%=*}"; v="${k#*=}"
          cs__isgitvar "$nm" && CS_LGENV=1
          cs__iscfgvar "$nm" && [ "$CS_LCFG" = 0 ] && CS_LCFG="$nm="
          case "$v" in *'$'*|*'`'*) cs__setvar "$nm" "" 0 ;; *) cs__setvar "$nm" "$v" 1 ;; esac
        done
        CS_R_ENV=0; cs__record assign
      else
        cs__record noop
      fi
      return 0
    fi
    w="${T[$i]}"
    # a command word held in a variable assigned a literal earlier in the line
    # (`C=/abs/coord.sh; $C commit-lock -- …`, `W=flock; $W f git commit`): read it
    # as that literal and look again (item 9) — an unknown one stays as it is
    case "$w" in
      *'$'*)
        if cs_expand "$w" && [ -n "$CS_E" ]; then
          case "$CS_E" in
            *[[:space:]]*) CS_R_VVAL="$CS_E" ;;           # several words (G="git -C /x"): not modelled
            *) T[i]="$CS_E"; TM[i]="$CS_E"; CS_R_VWRAP=1; continue ;;
          esac
        fi ;;
    esac
    base="${w##*/}"
    if [ "$base" = bash ] || [ "$base" = sh ]; then
      case "${T[$((i + 1))]:-}" in
        *'$'*) if cs_expand "${T[$((i + 1))]}" && [ -n "$CS_E" ]; then T[i + 1]="$CS_E"; TM[i + 1]="$CS_E"; CS_R_VWRAP=1; fi ;;
      esac
      if [ "${T[$((i + 1))]##*/}" = coord.sh ]; then i=$((i + 1)); continue; fi
    fi
    if [ "$base" = coord.sh ]; then
      case "${T[$((i + 1))]:-}" in
        commit-lock|gate-lock)
          j=$((i + 2))
          while [ "$j" -lt "$n" ] && [ "${T[$j]}" != "--" ]; do
            case "${T[$j]}" in --timeout|--id) j=$((j + 2)) ;; *) j=$((j + 1)) ;; esac
          done
          if [ "$j" -lt "$n" ]; then i=$((j + 1)); wrap=""; need_pos=0; continue; fi ;;
      esac
    fi
    break
  done
  case "$base" in fi|done|esac|case|for|select|function|'}'|'[['|'['|test|']]') CS_R_KW=1 ;; esac
  case "${TM[$i]:-}" in *$'\005'*) CS_R_QCMD=1 ;; esac      # a quoted / escaped command word
  # output redirections of the statement (every kind) — on the MARKED tokens: a
  # quoted '>' is \001 there and never a redirection
  local loose=0 t nx
  case "$base" in echo|printf|cat) loose=1 ;; esac
  j=$((i + 1)); [ "$PRE_REDIR" = 1 ] && j=0
  while [ "$j" -lt "$n" ]; do
    [ "$j" -eq "$i" ] && { j=$((j + 1)); continue; }
    t="${TM[$j]}"; nx="${TM[$((j + 1))]:-}"
    case "$t" in *'*'*|*'?'*|*'['*) CS_R_UGLOB=1 ;; esac   # an UNQUOTED glob char: the shell expands it
    cs__redir "$t" "$nx" "$loose"
    if [ -n "$CS_RT" ]; then
      CS_RT="${CS_RT//$'\001'/>}"; CS_RT="${CS_RT//$'\002'/*}"; CS_RT="${CS_RT//$'\003'/?}"; CS_RT="${CS_RT//$'\004'/[}"; CS_RT="${CS_RT//$'\005'/}"
      cs__resolve_target "$CS_RT"; CS_R_REDIR="$CS_R_REDIR${CS_R_REDIR:+$'\037'}$CS_RT2"
      [ "$CS_RSKIP" = 1 ] && j=$((j + 1))
    fi
    j=$((j + 1))
  done
  case "$base" in
    cd|pushd)
      j=$((i + 1)); while [ "$j" -lt "$n" ] && case "${T[$j]}" in --|-P|-L|-e|-@|-PL|-LP|-Pe|-eP) true ;; *) false ;; esac; do j=$((j + 1)); done
      raw="${T[$j]:-~}"
      if [ "$raw" = - ]; then CS_CUR=""; CS_CURRAW="cd -"
      elif cs_expand "$raw" && cs__abs "$CS_CUR" "$CS_E"; then
        if [ -d "$CS_P" ]; then CS_CUR=$(cs__canon_dir "$CS_P"); CS_CURRAW=""; fi   # a failing cd leaves the dir as is
      else CS_CUR=""; CS_CURRAW="$raw"; fi
      cs__record cd ;;
    popd) CS_CUR=""; CS_CURRAW="popd"; cs__record cd ;;
    eval)
      if [ "$depth" -lt 4 ]; then cs_scan "${T[*]:$((i + 1))}" $((depth + 1)) "$CS_R_ENV" "$CS_R_GENV"; else CS_RELIABLE=0; fi ;;
    bash|sh|zsh|dash|ksh)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        case "${T[$j]}" in
          -o|+o|-O|+O) j=$((j + 2)) ;;
          -*c)
            if [ $((j + 1)) -lt "$n" ]; then
              if [ "$depth" -lt 4 ]; then cs_scan "${T[$((j + 1))]}" $((depth + 1)) "$CS_R_ENV" "$CS_R_GENV"; else CS_RELIABLE=0; fi
              return 0
            fi
            break ;;
          -*) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      if [ "${T[$j]##*/}" = discover-tests.sh ]; then
        CS_R_ARGS=$(_gc_join "${T[@]:$((j + 1))}")
        for k in "${T[@]:$((j + 1))}"; do [ "$k" = run ] && CS_R_RUN=1; done
        cs__record st
      else cs__argcommit "$j"; cs__record other; fi ;;
    export|declare|typeset|readonly|local|set|source|.)
      CS_LEXP=1
      for k in "${T[@]:$((i + 1))}"; do
        _gc_is_assign "$k" || continue
        nm="${k%%=*}"; v="${k#*=}"
        cs__isgitvar "$nm" && CS_LGENV=1
        cs__iscfgvar "$nm" && [ "$CS_LCFG" = 0 ] && CS_LCFG="$nm="
        case "$v" in *'$'*|*'`'*) cs__setvar "$nm" "" 0 ;; *) cs__setvar "$nm" "$v" 1 ;; esac
      done
      [ "$CS_LGENV" = 1 ] && CS_R_GENV=1
      [ "$CS_LCFG" != 0 ] && CS_R_CFG="$CS_LCFG"
      case "$base" in source|.) cs__record other ;; *) cs__record export ;; esac ;;
    unset) cs__record assign ;;
    true|false|:|test|'['|'[['|']]'|fi|done|esac|'}'|then|else) cs__record noop ;;
    echo|printf|cat) cs__record echo ;;
    subteams-tests|discover-tests.sh)
      CS_R_ARGS=$(_gc_join "${T[@]:$((i + 1))}")
      for k in "${T[@]:$((i + 1))}"; do [ "$k" = run ] && CS_R_RUN=1; done
      cs__record st ;;
    git)
      j=$((i + 1)); dir="$CS_CUR"; raw="$CS_CURRAW"
      while [ "$j" -lt "$n" ]; do
        case "${T[$j]}" in
          -C|-C?*)
            if [ "${T[$j]}" = -C ]; then v="${T[$((j + 1))]:-}"; j=$((j + 2)); else v="${T[$j]#-C}"; j=$((j + 1)); fi
            if [ -n "$dir" ] && cs_expand "$v" && cs__abs "$dir" "$CS_E"; then dir="$CS_P"
            else dir=""; raw="${raw:-$v}"; fi ;;
          -c|-c?*)
            if [ "${T[$j]}" = -c ]; then v="${T[$((j + 1))]:-}"; j=$((j + 2)); else v="${T[$j]#-c}"; j=$((j + 1)); fi
            case "$(printf '%s' "${v%%=*}" | tr '[:upper:]' '[:lower:]')" in core.worktree|core.bare|include.path|includeif.*) CS_R_GENV=1 ;; esac
            cs__cfg_ok "$v" || { CS_R_GOPT=1; CS_R_CFG="${CS_R_CFG:-git -c ${v%%=*}}"; } ;;
          --literal-pathspecs) CS_R_LITPS=1; j=$((j + 1)) ;;
          --config-env|--config-env=*) CS_R_GENV=1; CS_R_GOPT=1; CS_R_CFG="${CS_R_CFG:---config-env}"
            case "${T[$j]}" in *=*) j=$((j + 1)) ;; *) j=$((j + 2)) ;; esac ;;
          --git-dir|--work-tree) CS_R_GENV=1; CS_R_GOPT=1; j=$((j + 2)) ;;
          --git-dir=*|--work-tree=*|--bare) CS_R_GENV=1; CS_R_GOPT=1; j=$((j + 1)) ;;
          --exec-path=*) CS_R_GOPT=1; CS_R_CFG="${CS_R_CFG:---exec-path}"; j=$((j + 1)) ;;
          --namespace|--super-prefix) j=$((j + 2)) ;;
          --exec-path) CS_R_GOPT=1; CS_R_CFG="${CS_R_CFG:---exec-path}"; j=$((j + 2)) ;;
          -*) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      if [ "$j" -ge "$n" ]; then cs__record noop; return 0; fi
      if [ -n "$dir" ] && [ -d "$dir" ]; then dir=$(cs__canon_dir "$dir"); fi
      CS_R_SUB="${T[$j]}"; CS_R_ARGS=$(_gc_join "${T[@]:$((j + 1))}")
      case "${TM[$j]:-}" in *$'\005'*) CS_R_QCMD=1 ;; esac    # a quoted / escaped git subcommand
      [ "$CS_R_DIRSET" = 1 ] || { CS_R_DIRSET=1; CS_R_DIR="$dir"; CS_R_DRAW="$raw"; }
      cs__record git ;;
    *)
      cs__argcommit $((i + 1))
      # a command word left as a $VAR (unknown, or several words: G="git -C /x"; $G
      # commit) with the word `commit` in the statement or in the variable's value
      case "$w" in
        *'$'*)
          local -a VW=()
          read -r -a VW <<< "$CS_R_VVAL"
          for k in "${T[@]:$((i + 1))}" ${VW[@]+"${VW[@]}"}; do [ "$k" = commit ] && CS_R_ACOMMIT=1; done ;;
      esac
      cs__record other ;;
  esac
  return 0
}

# ------------------------------------------------ what the commit will record
# Input: CS_REPO (toplevel of the target repo) + a cs_scan result. Uses tc_ct_*
# from scripts/lib-testclass.sh (sourced by the caller).
#   cs_parse_commit <args> [max]  the commit's own options -> CSP_*
#   cs_prior_ok <commit index>    the "only state-changing command" rule (B13) ->
#                                 CS_BAD (reason) / CS_REPLAY (add/stage/rm to replay)
#   cs_redir_bad <index>          output redirected into the repository -> CS_RB
#   cs_commit_tree <commit index> the tree git will record (B14) -> CS_TREE; rc 0 ok,
#                                 3 git would refuse (CS_CTERR), 2 unparsable,
#                                 4 the two readings of a split heredoc message differ
# git commit options for prefix resolution (git accepts unique abbreviations)
CS_LONG="all patch reuse-message reedit-message fixup squash reset-author short branch porcelain long null file author date message template signoff no-signoff trailer no-verify verify allow-empty allow-empty-message cleanup edit no-edit amend no-amend no-post-rewrite include no-include only no-only no-all no-patch pathspec-from-file pathspec-file-nul untracked-files verbose quiet dry-run status no-status gpg-sign no-gpg-sign interactive help"
CS_LONGV=" reuse-message reedit-message fixup squash file author date message template trailer cleanup pathspec-from-file "

cs__long() { # <name> -> CS_LO (full option name, "" unknown, "?" ambiguous)
  # The list is a subset of git's: ambiguous here => ambiguous in git => git refuses.
  local o hit="" c=0
  CS_LO=""
  for o in $CS_LONG; do
    [ "$o" = "$1" ] && { CS_LO="$o"; return 0; }
    case "$o" in "$1"*) hit="$o"; c=$((c + 1)) ;; esac
  done
  [ "$c" -eq 1 ] && CS_LO="$hit"
  [ "$c" -gt 1 ] && CS_LO="?"
  return 0
}

# cs_parse_commit <args \037-joined> [max args] — the commit's own options.
# Sets CSP_DRY CSP_ALL CSP_ONLY CSP_INC CSP_PATCH CSP_AMEND CSP_PFF (file or "") CSP_PFNUL,
# CSP_BAD (an ambiguous abbreviation: git refuses the command),
# CSP_PATHS[] and CSP_SPLIT (index of the first token with an unbalanced `$(`, -1 none).
cs_parse_commit() {
  local -a A; local a i=0 lim skip=0 rest=0 cl ch nm val opens closes
  IFS=$'\037' read -r -a A <<< "$1"
  lim="${2:-${#A[@]}}"
  CSP_BAD=""; CSP_DRY=0; CSP_ALL=0; CSP_ONLY=0; CSP_INC=0; CSP_PATCH=0; CSP_AMEND=0; CSP_PFF=""; CSP_PFNUL=0; CSP_PATHS=(); CSP_SPLIT=-1
  while [ "$i" -lt "${#A[@]}" ]; do
    a="${A[$i]}"
    if [ "$CSP_SPLIT" -lt 0 ]; then
      case "$a" in *'$('*)
        opens="${a//[!(]/}"; closes="${a//[!)]/}"
        [ "${#opens}" -gt "${#closes}" ] && CSP_SPLIT=$i ;;
      esac
    fi
    if [ "$i" -ge "$lim" ]; then i=$((i + 1)); continue; fi
    i=$((i + 1))
    if [ "$skip" = pff ]; then CSP_PFF="$a"; skip=0; continue; fi
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    if [ "$rest" -eq 1 ]; then CSP_PATHS+=("$a"); continue; fi
    case "$a" in
      --) rest=1 ;;
      --*)
        nm="${a#--}"; val=""; case "$nm" in *=*) val="${nm#*=}"; nm="${nm%%=*}" ;; esac
        cs__long "$nm"
        case "$CS_LO" in
          all) CSP_ALL=1 ;; no-all) CSP_ALL=0 ;;
          only) CSP_ONLY=1 ;; no-only) CSP_ONLY=0 ;;
          include) CSP_INC=1 ;; no-include) CSP_INC=0 ;;
          patch|interactive) CSP_PATCH=1 ;; no-patch) CSP_PATCH=0 ;;
          amend) CSP_AMEND=1 ;; no-amend) CSP_AMEND=0 ;;
          dry-run|help) CSP_DRY=1 ;;
          pathspec-file-nul) CSP_PFNUL=1 ;;
          pathspec-from-file) case "$a" in *=*) CSP_PFF="$val" ;; *) skip=pff ;; esac ;;
          '?') CSP_BAD="ambiguous option $a" ;;
          *) case "$CS_LONGV" in *" $CS_LO "*) case "$a" in *=*) ;; *) skip=1 ;; esac ;; esac ;;
        esac ;;
      -h) CSP_DRY=1 ;;
      -?*)
        cl="${a#-}"
        while [ -n "$cl" ]; do
          ch="${cl:0:1}"; cl="${cl:1}"
          case "$ch" in
            a) CSP_ALL=1 ;; o) CSP_ONLY=1 ;; i) CSP_INC=1 ;; p) CSP_PATCH=1 ;;
            m|F|C|c|t) [ -z "$cl" ] && skip=1; break ;;
            u|S) break ;;
          esac
        done ;;
      *) CSP_PATHS+=("$a") ;;
    esac
  done
}

cs_readonly_git() { # <sub> <args \037> -> 0 if it changes nothing
  local -a A; local a
  IFS=$'\037' read -r -a A <<< "$2"
  case "$1" in
    status|diff|log|show|rev-parse|ls-files|ls-tree|cat-file|describe|blame|grep|shortlog|version|help|check-ignore|rev-list|show-ref|for-each-ref|var|name-rev|count-objects|merge-base|whatchanged|diff-index|diff-files|diff-tree) ;;
    stash) case "${A[0]:-}" in list|show) ;; *) return 1 ;; esac ;;
    branch|remote)                     # listing forms only: no argument that names / changes something
      for a in ${A[@]+"${A[@]}"}; do
        case "$1:$a" in
          branch:--show-current|branch:-a|branch:-r|branch:-v|branch:-vv|branch:--list|branch:--all|branch:--remotes|branch:--verbose|branch:--no-color|branch:--color) ;;
          remote:-v|remote:--verbose) ;;
          *) return 1 ;;
        esac
      done ;;
    config) case "${A[0]:-}" in --get|--get-all|--get-regexp|--list|-l) ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
  case $'\037'"$2"$'\037' in
    *$'\037'--output*|*$'\037'-O*|*$'\037'--open-files-in-pager*) return 1 ;;
  esac
  return 0
}

cs__in_repo() { # <absolute path> -> 0 if inside CS_REPO (lexically, via its canonical dir, or as a symlink pointing in)
  local p="$1" d r l
  r="${CS_REPO%/}"
  case "$p/" in "$r"/*) return 0 ;; esac
  if [ -L "$p" ]; then                      # a file symlink outside the repo pointing at a tracked file
    l=$(readlink -f -- "$p" 2>/dev/null) || l=$(tc_realpath "$p" 2>/dev/null) || {
      # dangling and not resolvable: judge the link text itself (lexically)
      l=$(readlink -- "$p" 2>/dev/null) || return 0
      case "$l" in /*) ;; *) l="$(dirname -- "$p")/$l" ;; esac
    }
    case "$l/" in "$r"/*) return 0 ;; esac
  fi
  d=$(dirname -- "$p")
  while [ ! -d "$d" ] && [ "$d" != / ] && [ -n "$d" ]; do d=$(dirname -- "$d"); done
  d=$(cd -P -- "$d" 2>/dev/null && pwd) || return 0
  case "$d/" in "$r"/*) return 0 ;; esac
  return 1
}

cs_redir_bad() { # <statement index> -> CS_RB (the offending target) / rc 0 if it writes into the repo
  local -a R; local t
  CS_RB=""
  [ -n "${CS_REDIR[$1]}" ] || return 1
  IFS=$'\037' read -r -a R <<< "${CS_REDIR[$1]}"
  for t in "${R[@]}"; do
    case "$t" in '&'*|/dev/null|/dev/stdout|/dev/stderr|/dev/fd/*|/dev/tty) continue ;; esac
    if [ "$t" = "?" ] || cs__in_repo "$t"; then CS_RB="$t"; return 0; fi
  done
  return 1
}

cs_top_of() { # <dir> -> toplevel or rc 1
  [ -n "$1" ] && [ -d "$1" ] && git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

# The SHAPE a commit line must have under a contract (anything else is denied with
# CS_SHAPE_HELP — the gate then never has to guess what the line commits):
CS_SHAPE_HELP="write the commit as a plain command: [cd /abs &&] [git add <literal paths> &&] git commit [-a] [-m '…' | -F - <<'EOF'] [-- <paths>] [&& read-only follow-ups]"
CS_CONSUMERS=" tail head cat grep wc sort uniq less more column "

# cs_shape_ok <commit statement index> — the line-level shape (contract only):
# sequential ; && newline before the commit, no forbidden construct (cs__tokenize),
# nothing nested in bash -c / eval, no xargs commit, a pipe after the commit only
# into read-only consumers, no config / PATH injection up to the commit. Sets CS_BAD.
cs_shape_ok() {
  local ck="$1" j b
  CS_BAD=""
  if [ -n "$CS_SHAPE" ]; then CS_BAD="the line uses ${CS_SHAPE%%$'\n'*}"; return 1; fi
  for j in ${CS_KIND[@]+"${!CS_KIND[@]}"}; do
    [ "${CS_DEPTH[j]:-0}" = 0 ] || { CS_BAD="the commit line nests commands in bash -c / sh -c / eval ('${CS_TXT[j]}')"; return 1; }
    if [ "$j" -le "$ck" ] && [ "${CS_KW[j]:-0}" = 1 ]; then
      CS_BAD="the commit line uses shell control flow ('${CS_TXT[j]}': if/while/for/case/test/[ … ]) — the gate cannot know which branch runs"; return 1
    fi
    if [ "$j" -le "$ck" ] && [ "${CS_KIND[j]}" = git ]; then
      case "${CS_SUB[j]}" in *'$'*|*'`'*) CS_BAD="'${CS_TXT[j]}' computes the git subcommand at run time"; return 1 ;; esac
    fi
    if [ "${CS_ACOMMIT[j]:-0}" = 1 ]; then
      CS_BAD="'${CS_TXT[j]}' runs a git commit as an argument of a command the gate cannot model"; return 1
    fi
    if [ "$j" -lt "$ck" ] && cs__conditional "$j"; then
      if [ "${CS_KIND[j]}" = cd ] && ! cs__same_chain "$j" "$ck"; then
        CS_BAD="'${CS_TXT[j]}' runs only if an earlier command of its && chain succeeds — the gate cannot know the directory"; return 1
      fi
      if [ "${CS_KIND[j]}" = git ] && case "${CS_SUB[j]}" in add|stage|rm) true ;; *) false ;; esac && ! cs__same_chain "$j" "$ck"; then
        CS_BAD="'${CS_TXT[j]}' is conditional (an earlier command of its && chain may fail) and not chained to the commit with && — the gate cannot know whether it runs"; return 1
      fi
    fi
    if [ "$j" -lt "$ck" ]; then
      case "${CS_SEP[j]}" in ';'|A|n) ;; *) CS_BAD="'${CS_TXT[j]}' is joined to the next command by '${CS_SEP[j]}' before the commit"; return 1 ;; esac
    fi
    if [ "$j" -le "$ck" ] && [ -n "${CS_CFG[j]}" ]; then
      CS_BAD="'${CS_TXT[j]}' injects git configuration or binaries (${CS_CFG[j]}); allowed -c keys: user.name, user.email, commit.gpgsign, core.quotepath, color.*"; return 1
    fi
    if [ "$j" -gt "$ck" ] && [ "${CS_SEP[$((j - 1))]}" = '|' ]; then
      b="${CS_TXT[j]%% *}"; b="${b##*/}"
      case "$CS_CONSUMERS" in *" $b "*) ;; *) CS_BAD="the commit's output is piped into '$b' (only read-only consumers:${CS_CONSUMERS%?})"; return 1 ;; esac
      # a consumer runs WHILE the commit runs: its redirection into the repo races it
      if cs_redir_bad "$j"; then CS_BAD="'${CS_TXT[j]}' (piped from the commit) writes to '$CS_RB' inside the repository while the commit runs"; return 1; fi
    fi
  done
  [ "${CS_X[ck]}" = 1 ] && { CS_BAD="the commit takes arguments from stdin (xargs)"; return 1; }
  return 0
}

# cs__new_branch <sub> <args> -> 0 for exactly `checkout -b <new>` / `switch -c|--create
# <new>`: no start point, no other option — a new branch at HEAD changes neither
# the index nor the work tree, so the commit records the same tree (it only lands
# on the new branch). -B / -C (reset), --orphan, -t / --track, a start point: no.
cs__new_branch() {
  local -a A
  IFS=$'\037' read -r -a A <<< "$2"
  [ "${#A[@]}" -eq 2 ] || return 1
  case "$1:${A[0]}" in checkout:-b|switch:-c|switch:--create) ;; *) return 1 ;; esac
  case "${A[1]}" in ''|-*) return 1 ;; esac
  git check-ref-format --branch "${A[1]}" >/dev/null 2>&1
}

# cs__conditional <i> -> 0 if statement i sits behind an earlier element of its &&
# chain that can fail (anything but cd / add / stage / rm / assignment / export / echo)
cs__conditional() {
  local i=$(( $1 - 1 ))
  while [ "$i" -ge 0 ] && [ "${CS_SEP[i]}" = A ]; do
    case "${CS_KIND[i]}" in
      cd|assign|export|echo) ;;
      git) case "${CS_SUB[i]}" in add|stage|rm) ;; *) return 0 ;; esac ;;
      *) return 0 ;;
    esac
    i=$((i - 1))
  done
  return 1
}
cs__same_chain() { # <i> <k> -> 0 if statements i .. k are joined only by &&
  local i="$1"
  while [ "$i" -lt "$2" ]; do [ "${CS_SEP[i]}" = A ] || return 1; i=$((i + 1)); done
  return 0
}

# cs_prior_ok <commit statement index> — the shape (cs_shape_ok) plus the "only
# state-changing command" rule for what runs before the commit. Sets CS_BAD (deny
# text) and CS_REPLAY (indices of add/stage/rm to replay).
cs_prior_ok() {
  local ck="$1" j a rmnc=0 t
  local -a A
  CS_BAD=""; CS_REPLAY=()
  cs_shape_ok "$ck" || return 1
  for ((j = 0; j < ck; j++)); do
    if cs_redir_bad "$j"; then CS_BAD="'${CS_TXT[j]}' writes to '$CS_RB' (inside the repository) before the commit — run it separately first, then commit"; return 1; fi
    case "${CS_KIND[j]}" in
      assign|export|cd|noop|echo) continue ;;
      st) [ "${CS_RUN[j]}" = 1 ] || continue
          CS_BAD="run '${CS_TXT[j]}' separately first (it runs project code), then commit"; return 1 ;;
      other) CS_BAD="run '${CS_TXT[j]}' separately first, then commit — with a test contract the commit must be the only state-changing command of the line"; return 1 ;;
    esac
    # git ("read-only" with -c / --config-env / --exec-path can run anything)
    [ "${CS_GOPT[j]}" = 1 ] || ! cs_readonly_git "${CS_SUB[j]}" "${CS_ARGS[j]}" || continue
    [ "${CS_GOPT[j]}" = 1 ] || ! cs__new_branch "${CS_SUB[j]}" "${CS_ARGS[j]}" || continue
    case "${CS_SUB[j]}" in
      add|stage|rm)
        t=$(cs_top_of "${CS_DIR[j]}") || t=""
        if [ -z "$t" ] || [ "$t" != "$CS_REPO" ]; then CS_BAD="run '${CS_TXT[j]}' separately first (another or an unresolvable directory), then commit"; return 1; fi
        if [ "${CS_X[j]}" = 1 ]; then CS_BAD="'${CS_TXT[j]}' takes its paths from stdin (xargs) — run it separately first, then commit"; return 1; fi
        # quoted glob characters reach git as they are and are replayed exactly (git
        # matches the pathspec literally AND as a glob); unquoted ones the shell expands
        case "${CS_ARGS[j]}" in *'$'*|*'`'*)
          CS_BAD="'${CS_TXT[j]}' has dynamic arguments — run it separately first, then commit"; return 1 ;; esac
        [ "${CS_UGLOB[j]:-0}" = 1 ] && { CS_BAD="'${CS_TXT[j]}' has unquoted glob arguments (the shell expands them) — quote the paths or run it separately first, then commit"; return 1; }
        IFS=$'\037' read -r -a A <<< "${CS_ARGS[j]}"
        for a in ${A[@]+"${A[@]}"}; do
          case "$a" in
            -p|--patch|-i|--interactive|-e|--edit|--pathspec-from-file=-|-[!-]*p*|-[!-]*i*|-[!-]*e*)
              [ "${CS_SUB[j]}" = rm ] && case "$a" in -r|-rf|-fr|-q|-n|-f) continue ;; esac
              CS_BAD="'${CS_TXT[j]}' is interactive — stage separately first, then commit"; return 1 ;;
          esac
        done
        if [ "${CS_SUB[j]}" = rm ]; then
          case $'\037'"${CS_ARGS[j]}"$'\037' in *$'\037'--cached$'\037'*) ;; *) rmnc=1 ;; esac
        elif [ "$rmnc" -eq 1 ]; then
          CS_BAD="'git rm' without --cached followed by '${CS_TXT[j]}' in one line — run them separately, then commit"; return 1
        fi
        CS_REPLAY+=("$j") ;;
      *) CS_BAD="run '${CS_TXT[j]}' separately first, then commit — with a test contract the commit must be the only state-changing command of the line"; return 1 ;;
    esac
  done
  CS_RMNC=$rmnc
  return 0
}

# cs__tree_reading <commit index> [max args] -> CS_CT (tree); rc 0 ok, 3 git refuses
# (CS_CTERR), 2 unparsable (CS_CTERR), 1 internal error
cs__tree_reading() {
  local ck="$1" lim="${2:-}" j mode=plain rc f
  local -a A P
  CS_CT=""; CS_CTERR=""
  cs_parse_commit "${CS_ARGS[ck]}" $lim
  [ -z "$CSP_BAD" ] || { CS_CTERR="$CSP_BAD"; return 3; }
  P=()
  if [ "${CS_UGLOB[ck]:-0}" = 1 ]; then
    CS_CTERR="the commit has unquoted glob characters (the shell expands them, git would see something else) — quote the paths, use ':(literal)<path>', or stage them and commit without paths"; return 2
  fi
  for j in ${CSP_PATHS[@]+"${CSP_PATHS[@]}"}; do
    case "$j" in *'$'*|*'`'*)
      CS_CTERR="commit pathspec '$j' has dynamic characters — name the files literally"; return 2 ;;
    esac
    if [ "${CS_LITPS[ck]:-0}" = 1 ]; then P+=(":(literal)$j"); continue; fi   # git --literal-pathspecs
    P+=("$j")                    # quoted glob characters: git matches literally and as a glob — same on the replay
  done
  if [ -n "$CSP_PFF" ]; then
    case "$CSP_PFF" in -) CS_CTERR="--pathspec-from-file=- (stdin) cannot be checked before the commit runs"; return 2 ;; esac
    case "$CSP_PFF" in /*) f="$CSP_PFF" ;; *) f="${CS_DIR[ck]%/}/$CSP_PFF" ;; esac
    [ -f "$f" ] || { CS_CTERR="--pathspec-from-file: $CSP_PFF not found"; return 3; }
    if [ "$CSP_PFNUL" -eq 1 ]; then
      while IFS= read -r -d '' j; do P+=("$j"); done < "$f"
    else
      while IFS= read -r j || [ -n "$j" ]; do
        j="${j%$'\r'}"; [ -n "$j" ] || continue
        case "$j" in '"'*) CS_CTERR="--pathspec-from-file with C-quoted lines cannot be checked — stage separately"; return 2 ;; esac
        P+=("$j")
      done < "$f"
    fi
  fi
  if [ "$CSP_ALL" -eq 1 ] && [ "${#P[@]}" -gt 0 ]; then CS_CTERR="git commit -a with paths"; return 3; fi
  if [ "$CSP_ALL" -eq 1 ]; then mode=all
  elif [ "$CSP_INC" -eq 1 ]; then mode=include
  elif [ "$CSP_ONLY" -eq 1 ] || [ "${#P[@]}" -gt 0 ]; then mode=only; fi
  if [ "${CS_RMNC:-0}" -eq 1 ] && [ "$mode" != plain ]; then CS_CTERR="'git rm' without --cached before a commit with -a / paths"; return 2; fi
  tc_ct_begin "$CS_REPO" || { CS_CTERR="cannot create a temp index"; return 1; }
  for j in ${CS_REPLAY[@]+"${CS_REPLAY[@]}"}; do
    IFS=$'\037' read -r -a A <<< "${CS_ARGS[j]}"
    if [ "${CS_LITPS[j]:-0}" = 1 ]; then          # git --literal-pathspecs add …: replayed the same way
      if [ "${CS_SUB[j]}" = rm ]; then GIT_LITERAL_PATHSPECS=1 tc_ct_rm "${CS_DIR[j]}" ${A[@]+"${A[@]}"}; else GIT_LITERAL_PATHSPECS=1 tc_ct_add "${CS_DIR[j]}" ${A[@]+"${A[@]}"}; fi
    elif [ "${CS_SUB[j]}" = rm ]; then tc_ct_rm "${CS_DIR[j]}" ${A[@]+"${A[@]}"}; else tc_ct_add "${CS_DIR[j]}" ${A[@]+"${A[@]}"}; fi
    rc=$?; [ "$rc" -eq 0 ] || { CS_CTERR="$TC_ERR"; tc_ct_end; return "$rc"; }
  done
  tc_ct_commit "$CS_REPO" "${CS_DIR[ck]}" "$mode" ${P[@]+"${P[@]}"}; rc=$?
  CS_CT="$TC_CT_TREE"; CS_CTERR="$TC_ERR"
  tc_ct_end
  return "$rc"
}

# cs_commit_tree <commit index> -> CS_TREE; rc as cs__tree_reading, 4 = the two
# readings of a split message heredoc commit different trees
cs_commit_tree() {
  local ck="$1" ra rb ta tb
  CS_TREE=""
  cs__tree_reading "$ck"; ra=$?; ta="$CS_CT"
  [ "$CSP_SPLIT" -ge 0 ] || { CS_TREE="$ta"; return "$ra"; }
  cs__tree_reading "$ck" $((CSP_SPLIT + 1)); rb=$?; tb="$CS_CT"
  if [ "$ra" -eq 0 ] && [ "$rb" -eq 0 ]; then
    [ "$ta" = "$tb" ] && { CS_TREE="$ta"; return 0; }
    CS_CTERR="the commit message (a \$(…) heredoc with quotes inside) cannot be told apart from options/paths, and the two readings commit different content"
    return 4
  fi
  [ "$ra" -eq 0 ] && { CS_TREE="$ta"; return 0; }
  [ "$rb" -eq 0 ] && { CS_TREE="$tb"; return 0; }
  return "$ra"
}

