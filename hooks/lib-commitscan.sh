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
#   CS_SUBST[i] the first token that runs a command substitution ($(…) / backticks
#               INSIDE double quotes — the tokenizer keeps those as text), "" none.
#               Exempt: a commit-message heredoc `$(cat <<'EOF' … EOF)` (quoted
#               delimiter: literal body; unquoted: no further $( or backtick)
#   CS_GOPT[i]  git: 1 = global -c / --config-env / --exec-path options (a "read-
#               only" git command with them can run anything: diff.external …)
#   CS_RELIABLE 0 = the tokenizer was unsure (open quote, awk died, depth cap) —
#               the arrays may be incomplete
# Literal assignments seen so far are kept in CS_VN[] / CS_VV[] (bash 3.2: no
# associative arrays). Known limits (accepted, see the gate header): subshell
# scopes `( cd x )` are flattened (a cd inside parentheses is taken as leaking);
# `cd a || cd b` is read as both cds in sequence (|| / && are not modelled);
# aliases and functions are invisible.

CS_GITVARS='GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR'

cs__reset() {
  CS_KIND=(); CS_TXT=(); CS_SUB=(); CS_ARGS=(); CS_DIR=(); CS_DRAW=(); CS_ENV=(); CS_GENV=()
  CS_PEXP=(); CS_REDIR=(); CS_X=(); CS_RUN=(); CS_SUBST=(); CS_GOPT=()
  CS_VN=(); CS_VV=(); CS_RELIABLE=1; CS_CUR="$PWD"; CS_CURRAW=""; CS_LGENV=0; CS_LEXP=0
}

cs__isgitvar() { case " $CS_GITVARS " in *" $1 "*) return 0 ;; esac; return 1; }

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
cs_expand() {
  local w="$1" out="" re='^([^$`]*)\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))(.*)$'
  case "$w" in '~') w="${HOME:-}" ;; '~/'*) w="${HOME:-}/${w#\~/}" ;; esac
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
    '>'*) r="${r#>}"; r="${r#>}"; r="${r#|}" ;;
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

# cs__subst_ok <token> -> 0 unless it runs a command substitution: `$(` or a
# backtick in a token means a quoted "$(…)" / "`…`" the tokenizer kept as text
# (an unquoted one already split the statement). Exempt: a message heredoc.
# cs__heredoc_wellformed <raw command> -> 0 if EVERY "$(cat <<" in the raw text is
# the plain message form: delimiter, end of line, body, a line equal to the
# delimiter, then only whitespace and ")". Tokens lose newlines, so a token alone
# cannot show `<<'EOF' | sh`, `<<'EOF' >file` or a command after the terminator.
cs__heredoc_wellformed() {
  printf '%s' "$1" | LC_ALL=C awk 'BEGIN { RS = "\001" } { s = s $0 } END {
    rest = s
    while ((i = index(rest, "$(cat <<")) > 0) {
      rest = substr(rest, i + 8); dash = 0
      if (substr(rest, 1, 1) == "-") { dash = 1; rest = substr(rest, 2) }
      sub(/^[ \t]*/, "", rest)
      q = substr(rest, 1, 1)
      if (q == "\047" || q == "\"") {
        rest = substr(rest, 2); e = index(rest, q); if (!e) exit 1
        w = substr(rest, 1, e - 1); rest = substr(rest, e + 1)
      } else {
        if (!match(rest, /^[A-Za-z0-9_.-]+/)) exit 1
        w = substr(rest, 1, RLENGTH); rest = substr(rest, RLENGTH + 1)
      }
      if (w == "" || !match(rest, /^[ \t]*\n/)) exit 1
      rest = substr(rest, RLENGTH + 1); found = 0
      while (length(rest) > 0) {
        e = index(rest, "\n")
        if (e) { line = substr(rest, 1, e - 1); rest = substr(rest, e + 1) } else { line = rest; rest = "" }
        if (dash) sub(/^\t+/, "", line)
        if (line == w) { found = 1; break }
      }
      if (!found || !match(rest, /^[ \t\n]*\)/)) exit 1
      rest = substr(rest, RLENGTH + 1)
    }
    exit 0 }'
}

cs__subst_ok() {
  local t="$1" r w tail
  local q='^\$\(cat[[:space:]]+<<-?[[:space:]]*['"'"'"]([A-Za-z0-9_.-]+)['"'"'"][[:space:]](.*)$'
  local u='^\$\(cat[[:space:]]+<<-?[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]'
  case "$t" in *'$('*|*'`'*) ;; *) return 0 ;; esac
  [ "${CS_HDOK:-0}" = 1 ] || return 1          # a malformed / extended heredoc somewhere: no exemption
  if [[ $t =~ $q ]]; then
    # quoted delimiter: the body is literal up to the line "<W>"; what follows the
    # FIRST " <W> )" must not substitute again (no closing here: the message was
    # split by the tokenizer and the later tokens are checked on their own)
    w="${BASH_REMATCH[1]}"; r="${BASH_REMATCH[2]}"
    case "$r" in *" $w )"*) tail="${r#* "$w" )}" ;; *) return 0 ;; esac
    case "$tail" in *'$('*|*'`'*) return 1 ;; esac
    return 0
  fi
  if [[ $t =~ $u ]]; then           # unquoted delimiter: the body is expanded
    r="${t#??}"; case "$r" in *'$('*|*'`'*) return 1 ;; esac
    return 0
  fi
  return 1
}

cs__record() { # <kind> <tokens from index i…> uses locals of cs__stmt via dynamic scope
  local k=${#CS_KIND[@]} txt
  txt="${CS_STMT_TXT:0:100}"
  CS_KIND[k]="$1"; CS_TXT[k]="$txt"; CS_SUB[k]="${CS_R_SUB:-}"; CS_ARGS[k]="${CS_R_ARGS:-}"
  if [ "$CS_R_DIRSET" = 1 ]; then CS_DIR[k]="$CS_R_DIR"; CS_DRAW[k]="$CS_R_DRAW"; else CS_DIR[k]="$CS_CUR"; CS_DRAW[k]="$CS_CURRAW"; fi
  CS_ENV[k]="$CS_R_ENV"; CS_GENV[k]="$CS_R_GENV"; CS_PEXP[k]="$CS_LEXP"
  CS_REDIR[k]="$CS_R_REDIR"; CS_X[k]="$CS_R_X"; CS_RUN[k]="${CS_R_RUN:-0}"
  CS_SUBST[k]="$CS_R_SUBST"; CS_GOPT[k]="${CS_R_GOPT:-0}"
}

# cs_scan "<command line>" [depth] [inherited env 0/1] [inherited git env 0/1]
cs_scan() {
  local depth="${2:-0}" pe="${3:-0}" pg="${4:-0}" line sentinel=0
  if [ "$depth" -eq 0 ]; then
    cs__reset; CS_HDOK=1
    case "$1" in *'$(cat <<'*) cs__heredoc_wellformed "$1" || CS_HDOK=0 ;; esac
  fi
  local -a T
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      $'\036OK') sentinel=1; continue ;;
      $'\036BAD') continue ;;
    esac
    IFS=$'\037' read -r -a T <<< "$line"
    cs__stmt "$depth" "$pe" "$pg"
  done < <(printf '%s' "$1" | _gc_tokenize)
  [ "$sentinel" -eq 1 ] || CS_RELIABLE=0
}

cs__stmt() { # uses T from cs_scan
  local depth="$1" n=${#T[@]} i=0 w base wrap="" need_pos=0 j k v nm assigns=0 dir d raw
  local CS_R_ENV="$2" CS_R_GENV="$3" CS_R_X=0 CS_R_REDIR="" CS_R_SUB="" CS_R_ARGS="" CS_R_RUN=0 CS_STMT_TXT
  local CS_R_SUBST="" CS_R_GOPT=0
  local CS_R_DIR="" CS_R_DRAW="" CS_R_DIRSET=0
  [ "$CS_LGENV" = 1 ] && CS_R_GENV=1
  CS_STMT_TXT=$(printf '%s ' "${T[@]}" | tr -d '\000-\037'); CS_STMT_TXT="${CS_STMT_TXT% }"
  for w in "${T[@]}"; do cs__subst_ok "$w" || { CS_R_SUBST="$w"; break; }; done
  while :; do
    while [ "$i" -lt "$n" ]; do
      w="${T[$i]}"
      case "$w" in
        '!'|if|then|else|elif|do|while|until|'{'|time|exec|nohup|builtin|command|sudo|doas|nice|ionice|stdbuf|setsid|timeout|flock|xargs)
          wrap="$w"; i=$((i + 1))
          case "$w" in timeout|flock) need_pos=1 ;; *) need_pos=0 ;; esac
          [ "$w" = xargs ] && CS_R_X=1
          continue ;;
        env) wrap=env; CS_R_ENV=1; i=$((i + 1)); continue ;;
        -*)
          if [ -n "$wrap" ]; then
            case "$wrap:$w" in
              env:-C|env:--chdir) CS_R_DIRSET=1; CS_R_DIR=""; CS_R_DRAW="env -C ${T[$((i + 1))]:-}"; i=$((i + 2)) ;;
              env:-u|env:-S|env:--unset|sudo:-u|sudo:-g|sudo:-h|sudo:-C|sudo:-p|sudo:-r|sudo:-t|sudo:-U|doas:-u|doas:-C|nice:-n|ionice:-c|ionice:-n|ionice:-p|ionice:-P|ionice:-t|timeout:-s|timeout:-k|stdbuf:-i|stdbuf:-o|stdbuf:-e|flock:-w|flock:-E|xargs:-I|xargs:-n|xargs:-P|xargs:-L|xargs:-d|xargs:-E|xargs:-s|xargs:-a)
                i=$((i + 2)) ;;
              *) i=$((i + 1)) ;;
            esac
            continue
          fi
          break ;;
      esac
      if [ "$need_pos" -eq 1 ] && [ -n "$wrap" ]; then need_pos=0; i=$((i + 1)); continue; fi
      if _gc_is_assign "$w"; then
        nm="${w%%=*}"; assigns=$((assigns + 1))
        cs__isgitvar "$nm" && CS_R_GENV=1
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
          case "$v" in *'$'*|*'`'*) cs__setvar "$nm" "" 0 ;; *) cs__setvar "$nm" "$v" 1 ;; esac
        done
        CS_R_ENV=0; cs__record assign
      else
        cs__record noop
      fi
      return 0
    fi
    w="${T[$i]}"; base="${w##*/}"
    if [ "$base" = bash ] || [ "$base" = sh ]; then
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
  # output redirections of the statement (every kind)
  local loose=0 t nx
  case "$base" in echo|printf|cat) loose=1 ;; esac
  j=$((i + 1))
  while [ "$j" -lt "$n" ]; do
    t="${T[$j]}"; nx="${T[$((j + 1))]:-}"
    cs__redir "$t" "$nx" "$loose"
    if [ -n "$CS_RT" ]; then
      cs__resolve_target "$CS_RT"; CS_R_REDIR="$CS_R_REDIR${CS_R_REDIR:+$'\037'}$CS_RT2"
      [ "$CS_RSKIP" = 1 ] && j=$((j + 1))
    fi
    j=$((j + 1))
  done
  case "$base" in
    cd|pushd)
      j=$((i + 1)); while [ "$j" -lt "$n" ] && [ "${T[$j]}" = "--" ]; do j=$((j + 1)); done
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
      else cs__record other; fi ;;
    export|declare|typeset|readonly|local|set|source|.)
      CS_LEXP=1
      for k in "${T[@]:$((i + 1))}"; do
        _gc_is_assign "$k" || continue
        nm="${k%%=*}"; v="${k#*=}"
        cs__isgitvar "$nm" && CS_LGENV=1
        case "$v" in *'$'*|*'`'*) cs__setvar "$nm" "" 0 ;; *) cs__setvar "$nm" "$v" 1 ;; esac
      done
      [ "$CS_LGENV" = 1 ] && CS_R_GENV=1
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
          -C)
            v="${T[$((j + 1))]:-}"
            if [ -n "$dir" ] && cs_expand "$v" && cs__abs "$dir" "$CS_E"; then dir="$CS_P"
            else dir=""; raw="${raw:-$v}"; fi
            j=$((j + 2)) ;;
          -c)
            v="${T[$((j + 1))]:-}"
            case "$(printf '%s' "${v%%=*}" | tr '[:upper:]' '[:lower:]')" in core.worktree|core.bare|include.path|includeif.*) CS_R_GENV=1 ;; esac
            CS_R_GOPT=1; j=$((j + 2)) ;;
          --git-dir|--work-tree|--config-env) CS_R_GENV=1; CS_R_GOPT=1; j=$((j + 2)) ;;
          --git-dir=*|--work-tree=*|--config-env=*|--bare) CS_R_GENV=1; CS_R_GOPT=1; j=$((j + 1)) ;;
          --exec-path=*) CS_R_GOPT=1; j=$((j + 1)) ;;
          --namespace|--super-prefix) j=$((j + 2)) ;;
          --exec-path) CS_R_GOPT=1; j=$((j + 2)) ;;
          -*) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      if [ "$j" -ge "$n" ]; then cs__record noop; return 0; fi
      if [ -n "$dir" ] && [ -d "$dir" ]; then dir=$(cs__canon_dir "$dir"); fi
      CS_R_SUB="${T[$j]}"; CS_R_ARGS=$(_gc_join "${T[@]:$((j + 1))}")
      [ "$CS_R_DIRSET" = 1 ] || { CS_R_DIRSET=1; CS_R_DIR="$dir"; CS_R_DRAW="$raw"; }
      cs__record git ;;
    *) cs__record other ;;
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
  case "$1" in
    status|diff|log|show|rev-parse|ls-files|ls-tree|cat-file|describe|blame|grep|shortlog|version|help|check-ignore|rev-list|show-ref|for-each-ref|var|name-rev|count-objects|merge-base|whatchanged|diff-index|diff-files|diff-tree) ;;
    *) return 1 ;;
  esac
  case $'\037'"$2"$'\037' in
    *$'\037'--output*|*$'\037'-O*|*$'\037'--open-files-in-pager*) return 1 ;;
  esac
  return 0
}

cs__in_repo() { # <absolute path> -> 0 if inside CS_REPO (lexically or via its canonical dir)
  local p="$1" d r
  r="${CS_REPO%/}"
  case "$p/" in "$r"/*) return 0 ;; esac
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

# cs_prior_ok <commit statement index> — the "only state-changing command" rule.
# Sets CS_BAD (deny text) and CS_REPLAY (indices of add/stage/rm to replay).
cs_prior_ok() {
  local ck="$1" j a rmnc=0 t
  local -a A
  CS_BAD=""; CS_REPLAY=()
  for ((j = 0; j <= ck; j++)); do
    if [ -n "${CS_SUBST[j]}" ]; then
      CS_BAD="'${CS_TXT[j]}' runs a command substitution (${CS_SUBST[j]:0:60}) — it executes before the commit; run it separately first. For the message use git commit -F - <<'EOF' … EOF"
      return 1
    fi
    [ "$j" -lt "$ck" ] || break
    if cs_redir_bad "$j"; then CS_BAD="'${CS_TXT[j]}' writes to '$CS_RB' (inside the repository) before the commit — run it separately first, then commit"; return 1; fi
    case "${CS_KIND[j]}" in
      assign|export|cd|noop|echo) continue ;;
      st) CS_BAD="run '${CS_TXT[j]}' separately first (it runs project code), then commit"; return 1 ;;
      other) CS_BAD="run '${CS_TXT[j]}' separately first, then commit — with a test contract the commit must be the only state-changing command of the line"; return 1 ;;
    esac
    # git ("read-only" with -c / --config-env / --exec-path can run anything)
    [ "${CS_GOPT[j]}" = 1 ] || ! cs_readonly_git "${CS_SUB[j]}" "${CS_ARGS[j]}" || continue
    case "${CS_SUB[j]}" in
      add|stage|rm)
        t=$(cs_top_of "${CS_DIR[j]}") || t=""
        if [ -z "$t" ] || [ "$t" != "$CS_REPO" ]; then CS_BAD="run '${CS_TXT[j]}' separately first (another or an unresolvable directory), then commit"; return 1; fi
        if [ "${CS_X[j]}" = 1 ]; then CS_BAD="'${CS_TXT[j]}' takes its paths from stdin (xargs) — run it separately first, then commit"; return 1; fi
        case "${CS_ARGS[j]}" in *'$'*|*'`'*|*'*'*|*'?'*|*'['*)
          CS_BAD="'${CS_TXT[j]}' has dynamic or glob arguments — run it separately first, then commit"; return 1 ;; esac
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
  for j in ${CSP_PATHS[@]+"${CSP_PATHS[@]}"}; do
    case "$j" in *'*'*|*'?'*|*'['*|*'$'*|*'`'*)
      CS_CTERR="commit pathspec '$j' has glob or dynamic characters (the shell and git would expand it differently) — name the files, or stage them and commit without paths"; return 2 ;;
    esac
  done
  P=(${CSP_PATHS[@]+"${CSP_PATHS[@]}"})
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
    if [ "${CS_SUB[j]}" = rm ]; then tc_ct_rm "${CS_DIR[j]}" ${A[@]+"${A[@]}"}; else tc_ct_add "${CS_DIR[j]}" ${A[@]+"${A[@]}"}; fi
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

