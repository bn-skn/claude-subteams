#!/bin/bash
# shellcheck disable=SC2034  # GC_* are the library interface, read by the sourcing hook
# Shared helper (sourced, never executed) for the Bash-matcher hooks that need to
# know WHICH git commands a shell command line really runs: pre-commit-gate,
# pre-push-check. Replaces per-hook regexes that missed `git -c x=y commit`,
# `env git`, `bash -c "…"`, `if …; then git commit` and tripped on
# `echo "…git commit…"` / `git commit-tree`.
#
# gitcmd_scan "<command line>" fills (one slot per git invocation, in command
# order; everything is reset on every top-level call):
#   GC_SUB[i]   subcommand ("commit", "add", "push", …)
#   GC_ARGS[i]  its arguments, joined by $'\037' (split with IFS=$'\037' read -a);
#               redirections (`2>&1`, `> f`) already removed
#   GC_DIR[i]   value of the last `git -C <dir>` (or "")
#   GC_CD[i]    target of the last `cd`/`pushd` seen before this invocation (or "")
#   GC_X[i]     1 if the invocation sits behind `xargs` (its real arguments come
#               from stdin and are unknowable here)
#   GC_RELIABLE 1 if the parse is trustworthy, 0 if not: a quote still open at the
#               end of input, the tokenizer produced no end-of-parse sentinel
#               (awk died), or `bash -c`/`eval` nesting went past the depth cap.
#               When 0 the arrays may be incomplete — CALLERS MUST fall back to
#               their old, conservative detection (never trust an empty result).
#
# The tokenizer is a quote-aware awk state machine fed through STDIN (a huge
# command in the environment would hit E2BIG): text inside '…' / "…" / $'…' stays
# one word, so `echo "a; git commit"` is a single echo; unquoted && || ; | & ( ) `
# and newlines end a statement; heredoc bodies (`<<EOF`, `<<-'EOF'`) outside quotes
# are skipped up to their terminator. Each statement then loses wrapper prefixes
# (VAR=x, env, command, time, sudo/doas, timeout, flock, stdbuf, ionice, nice,
# xargs, if/then/do, `{`, `!`), and `bash|sh|zsh [-o x] -c "…"` / `eval` are
# scanned recursively (depth-capped).
# Known limits: `$(…)` inside double quotes is plain quoted text (not scanned —
# fine for commit messages, a miss for `echo "$(git commit)"`); shell aliases and
# functions are invisible. Misses degrade toward "no git command seen", which is
# why callers keep a legacy fallback only for the unreliable case — do not read
# this list as "all fail toward the old behaviour".

GC_SUB=(); GC_ARGS=(); GC_DIR=(); GC_CD=(); GC_X=()
GC_LASTCD=""; GC_RELIABLE=1

_gc_tokenize() { # command text on stdin -> one statement per line (tokens joined by \037), last line \036OK|\036BAD
  LC_ALL=C awk '
    function flush() { if (has) { out = out (nt++ ? US : "") tok } tok = ""; has = 0 }
    function endstmt() { flush(); if (nt) print out; out = ""; nt = 0 }
    BEGIN { RS = "\001"; US = "\037"; s = ""; q = ""; tok = ""; has = 0; out = ""; nt = 0; nh = 0; ar = 0; bad = 0 }
    { s = s $0 }
    END {
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q == "\047") { if (c == "\047") q = ""; else tok = tok (c == "\n" ? " " : c); continue }
        if (q == "A") {
          if (c == "\\") { tok = tok substr(s, i + 1, 1); i++ }
          else if (c == "\047") q = ""
          else tok = tok (c == "\n" ? " " : c)
          continue
        }
        if (q == "\"") {
          if (c == "\\") {
            nx = substr(s, i + 1, 1)
            if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { tok = tok nx; i++ } else tok = tok c
            continue
          }
          if (c == "\"") q = ""; else tok = tok (c == "\n" ? " " : c)
          continue
        }
        if (c == "\\") {
          nx = substr(s, i + 1, 1); i++
          if (nx != "\n") { tok = tok nx; has = 1 }
          continue
        }
        if (c == "$" && substr(s, i + 1, 1) == "\047") { q = "A"; has = 1; i++; continue }
        if (c == "\047" || c == "\"") { q = c; has = 1; continue }
        if (c == " " || c == "\t") { flush(); continue }
        if (c == "#" && !has) { while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
        if (ar == 0 && c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") {
          j = i + 2; dash = 0
          if (substr(s, j, 1) == "-") { dash = 1; j++ }
          while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
          w = ""; qc = substr(s, j, 1)
          if (qc == "\047" || qc == "\"") {
            j++
            while (j <= n && substr(s, j, 1) != qc) { w = w substr(s, j, 1); j++ }
            j++
          } else {
            while (j <= n && substr(s, j, 1) !~ /[ \t\n;|&()<>]/) { w = w substr(s, j, 1); j++ }
          }
          gsub(/\\/, "", w)
          if (w != "") { hw[nh] = w; hd[nh] = dash; nh++ }
          tok = tok "<<" w; has = 1; i = j - 1
          continue
        }
        # arithmetic context `$((…))` / `((…))`: `<<` there is a shift, not a heredoc
        if (c == "(") { if (ar > 0 || substr(s, i - 1, 1) == "(") ar += (ar > 0 ? 1 : 2) }
        else if (c == ")" && ar > 0) ar--
        if (c == "\n" || c == ";" || c == "|" || c == "(" || c == ")" || c == "`") {
          endstmt()
          if (c == "\n" && nh > 0) {
            for (h = 0; h < nh; h++) {
              found = 0
              while (i < n) {
                e = index(substr(s, i + 1), "\n")
                if (e == 0) { line = substr(s, i + 1); i = n } else { line = substr(s, i + 1, e - 1); i = i + e }
                if (hd[h]) sub(/^\t+/, "", line)
                if (line == hw[h]) { found = 1; break }
              }
              if (!found) bad = 1   # terminator never found: we swallowed the tail, parse is not trustworthy
            }
            nh = 0
          }
          continue
        }
        if (c == "&") {
          pv = substr(s, i - 1, 1); nx = substr(s, i + 1, 1)
          if (pv == ">" || pv == "<" || nx == ">") { tok = tok c; has = 1 } else endstmt()
          continue
        }
        tok = tok c; has = 1
      }
      endstmt()
      print (q == "" && !bad ? "\036OK" : "\036BAD")
    }'
}

_gc_join() { # args... -> joined by \037, dropping redirections (bash 3.2: case globs, no regex)
  local out="" first=1 w x skip=0
  for w in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    x="${w#"${w%%[!0-9&]*}"}"   # drop a leading run of fd digits / &
    case "$x" in
      '>'|'>>'|'<'|'<<'|'<<<'|'>|') skip=1; continue ;;
      '>'*|'<'*) continue ;;
    esac
    if [ "$first" -eq 1 ]; then out="$w"; first=0; else out="$out"$'\037'"$w"; fi
  done
  printf '%s' "$out"
}

_gc_is_assign() { # word -> 0 if VAR=value
  local n
  case "$1" in *=*) ;; *) return 1 ;; esac
  n="${1%%=*}"
  case "$n" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; esac
  return 0
}

gitcmd_scan() { # $1 = command line, $2 = recursion depth (internal)
  if [ -z "${2:-}" ]; then GC_SUB=(); GC_ARGS=(); GC_DIR=(); GC_CD=(); GC_X=(); GC_LASTCD=""; GC_RELIABLE=1; fi
  local depth="${2:-0}" line i n w wrap need_pos xargs base j dir sub k sentinel=0
  local -a T
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      $'\036OK') sentinel=1; continue ;;
      $'\036BAD') continue ;;
    esac
    IFS=$'\037' read -r -a T <<< "$line"
    n=${#T[@]}; i=0; wrap=""; need_pos=0; xargs=0
    while :; do
      while [ "$i" -lt "$n" ]; do
        w="${T[$i]}"
        case "$w" in
          '!'|if|then|else|elif|do|while|until|'{'|time|exec|nohup|builtin|command|env|sudo|doas|nice|ionice|stdbuf|setsid|timeout|flock|xargs)
            wrap="$w"; i=$((i + 1))
            case "$w" in timeout|flock) need_pos=1 ;; *) need_pos=0 ;; esac
            [ "$w" = xargs ] && xargs=1
            continue ;;
          -*)
            if [ -n "$wrap" ]; then
              case "$wrap:$w" in
                env:-u|env:-C|env:-S|env:--unset|env:--chdir|sudo:-u|sudo:-g|sudo:-h|sudo:-C|sudo:-p|sudo:-r|sudo:-t|sudo:-U|doas:-u|doas:-C|nice:-n|ionice:-c|ionice:-n|ionice:-p|ionice:-P|ionice:-t|timeout:-s|timeout:-k|stdbuf:-i|stdbuf:-o|stdbuf:-e|flock:-w|flock:-E|xargs:-I|xargs:-n|xargs:-P|xargs:-L|xargs:-d|xargs:-E|xargs:-s|xargs:-a)
                  i=$((i + 2)) ;;
                *) i=$((i + 1)) ;;
              esac
              continue
            fi
            break ;;
        esac
        if [ "$need_pos" -eq 1 ] && [ -n "$wrap" ]; then need_pos=0; i=$((i + 1)); continue; fi  # timeout DURATION / flock FILE
        if _gc_is_assign "$w"; then wrap=""; i=$((i + 1)); continue; fi
        break
      done
      [ "$i" -lt "$n" ] || break
      # `coord.sh commit-lock -- CMD…` / `coord.sh gate-lock [--timeout N] -- CMD…`
      # (the multi-instance protocol wraps commits this way): the real command
      # starts after `--`; also `bash coord.sh …`.
      w="${T[$i]}"; base="${w##*/}"
      if [ "$base" = bash ] || [ "$base" = sh ]; then
        w="${T[$((i + 1))]:-}"
        if [ "${w##*/}" = coord.sh ]; then i=$((i + 1)); continue; fi
        w="${T[$i]}"
      fi
      if [ "$base" = "coord.sh" ]; then
        case "${T[$((i + 1))]:-}" in
          commit-lock|gate-lock)
            j=$((i + 2))
            while [ "$j" -lt "$n" ] && [ "${T[$j]}" != "--" ]; do
              case "${T[$j]}" in --timeout|--id) j=$((j + 2)) ;; *) j=$((j + 1)) ;; esac
            done
            [ "$j" -lt "$n" ] || break
            i=$((j + 1)); wrap=""; need_pos=0
            continue ;;
        esac
      fi
      break
    done
    [ "$i" -lt "$n" ] || continue
    w="${T[$i]}"; base="${w##*/}"
    case "$base" in
      cd|pushd)
        j=$((i + 1))
        while [ "$j" -lt "$n" ] && [ "${T[$j]}" = "--" ]; do j=$((j + 1)); done
        [ "$j" -lt "$n" ] && GC_LASTCD="${T[$j]}"
        ;;
      eval)
        if [ "$depth" -lt 4 ]; then
          gitcmd_scan "${T[*]:$((i + 1))}" $((depth + 1))
        else
          GC_RELIABLE=0
        fi
        ;;
      bash|sh|zsh|dash|ksh)
        j=$((i + 1))
        while [ "$j" -lt "$n" ]; do
          case "${T[$j]}" in
            -o|+o|-O|+O) j=$((j + 2)) ;;
            -*c)
              if [ $((j + 1)) -lt "$n" ]; then
                if [ "$depth" -lt 4 ]; then gitcmd_scan "${T[$((j + 1))]}" $((depth + 1)); else GC_RELIABLE=0; fi
              fi
              break ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      git)
        j=$((i + 1)); dir=""
        while [ "$j" -lt "$n" ]; do
          case "${T[$j]}" in
            -C) dir="${T[$((j + 1))]:-}"; j=$((j + 2)) ;;
            -c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix) j=$((j + 2)) ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        [ "$j" -lt "$n" ] || continue
        sub="${T[$j]}"
        k=${#GC_SUB[@]}
        GC_SUB[k]="$sub"
        GC_ARGS[k]="$(_gc_join "${T[@]:$((j + 1))}")"
        GC_DIR[k]="$dir"
        GC_CD[k]="$GC_LASTCD"
        GC_X[k]="$xargs"
        ;;
    esac
  done < <(printf '%s' "$1" | _gc_tokenize)
  # Every tokenizer run must end with its OK sentinel: missing = awk died, BAD =
  # a quote was still open at the end of input.
  if [ "$sentinel" -ne 1 ]; then GC_RELIABLE=0; fi
}
