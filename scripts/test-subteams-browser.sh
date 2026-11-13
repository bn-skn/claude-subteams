#!/usr/bin/env bash
# test-subteams-browser.sh — регрессия bin/subteams-browser (план 1.50.0, Задача 2.2).
# Всё во временном каталоге: подменённые npm и agent-browser, свой HOME, XDG_CACHE_HOME и PATH
# (из набора символических ссылок на нужные утилиты — без системного Chrome и agent-browser).
# Сеть, настоящий npm и боевой кэш пользователя не трогаются.
# Отрицательный контроль: SUBTEAMS_BROWSER=<путь к изменённой копии> bash scripts/test-subteams-browser.sh
#   (копия должна лежать в <корень>/bin/ рядом с <корень>/deps/agent-browser/).
# Использование: bash scripts/test-subteams-browser.sh   (exit 0 = все PASS, иначе 1)
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="${SUBTEAMS_BROWSER:-$DIR/bin/subteams-browser}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-subteams-browser-XXXXXX")
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

FAILS=0; PASSES=0
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS $1"; PASSES=$((PASSES+1))
  else echo "FAIL $1: expected [$2] got [$3]"; FAILS=$((FAILS+1)); fi
}
names() { # <dir> -> имена записей (включая скрытые), по одной в строке
  local f
  for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then basename "$f"; fi
  done
}
contains() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }

SENT="sentinel-$$-c0ffee-do-not-print"

# --- набор утилит без браузеров и без agent-browser -------------------------
TOOLS="$TMP/tools"; mkdir -p "$TOOLS"
for t in bash sh env uname mkdir rm mv cp mktemp cat date find sleep sha1sum shasum openssl git \
         dirname basename readlink wc tr cut sed ls pkill chmod touch grep head node; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -s "$p" "$TOOLS/$t"
done
[ -e "$TOOLS/node" ] || { echo "node required"; exit 2; }
[ -e "$TOOLS/git" ] || { echo "git required"; exit 2; }

# --- подделки ----------------------------------------------------------------
mkfake_ab() { # <путь> <версия> <метка>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = --version ]; then echo "agent-browser $2"; exit 0; fi
log="\${FAKE_AB_LOG:-/dev/null}"
{ printf 'WHO=%s\n' "$3"; printf 'ARGC=%s\n' "\$#"; for a in "\$@"; do printf '[%s]\n' "\$a"; done
  printf 'SKILLS=%s\n' "\${AGENT_BROWSER_SKILLS_DIR:-}"; } >> "\$log"
shot=0; last=""; for a in "\$@"; do [ "\$a" = screenshot ] && shot=1; last="\$a"; done
if [ "\$shot" = 1 ] && [ "\${FAKE_AB_RC:-0}" = 0 ]; then case "\$last" in *.png) printf 'PNGDATA' > "\$last" ;; esac; fi
exit "\${FAKE_AB_RC:-0}"
EOF
  chmod +x "$1"
}
mkfake_ab "$TMP/sys-same/agent-browser" 0.43.0 system
mkfake_ab "$TMP/sys-other/agent-browser" 0.42.0 system-old
mkfake_ab "$TMP/override/ab" 9.9.9 override
mkfake_ab "$TMP/fake-installed-ab" 0.43.0 cache
mkfake_ab "$TMP/fake-installed-ab-old" 0.42.0 cache-old

mkdir -p "$TMP/chrome"; printf '#!/bin/sh\nexit 0\n' > "$TMP/chrome/google-chrome"; chmod +x "$TMP/chrome/google-chrome"

mkdir -p "$TMP/npm"
cat > "$TMP/npm/npm" <<EOF
#!/usr/bin/env bash
# подменённый npm: пишет вызов в журнал, имитирует установку дерева agent-browser
printf '%s|%s\n' "\$PWD" "\$*" >> "\${FAKE_NPM_LOG:-/dev/null}"
[ "\${FAKE_NPM_IGNORE_TERM:-0}" = 1 ] && trap '' TERM   # глухой к TERM: снять может только KILL
env   # «болтливый» npm: окружение уходит в его лог, а не в вывод обёртки
sleep "\${FAKE_NPM_SLEEP:-0}"
mkdir -p node_modules/agent-browser/skill-data/core
src="$TMP/fake-installed-ab"; [ "\${FAKE_INSTALL_VER:-0.43.0}" = 0.43.0 ] || src="$TMP/fake-installed-ab-old"
for p in cli-linux-x64-gnu cli-linux-x64-musl cli-linux-arm64-gnu cli-linux-arm64-musl cli-darwin-x64 cli-darwin-arm64; do
  mkdir -p "node_modules/@agent-browser/\$p/bin"; cp "\$src" "node_modules/@agent-browser/\$p/bin/agent-browser"
done
[ "\${FAKE_NPM_FAIL:-0}" = 1 ] && { echo "npm ERR! simulated" >&2; exit 1; }
exit 0
EOF
chmod +x "$TMP/npm/npm"

HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR" "$TMP/t"
NPMLOG="$TMP/npm.log"; ABLOG="$TMP/ab.log"; ALLOUT="$TMP/all-output"
: > "$ALLOUT"

CACHE=""; CWD="$TMP"
newcache() { CACHE="$TMP/cache-$1"; mkdir -p "$CACHE"; : > "$NPMLOG"; : > "$ABLOG"; }
abdir() { echo "$CACHE/claude-subteams/agent-browser"; }

RC=0; OUT=""; ERR=""
# run <PATH> [VAR=val ...] -- <аргументы subteams-browser>
run() {
  local path="$1"; shift
  local -a extra=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do extra+=("$1"); shift; done
  shift
  (cd "$CWD" && env -i HOME="$HOMEDIR" XDG_CACHE_HOME="$CACHE" PATH="$path" TMPDIR="$TMP/t" \
     SUBTEAMS_TEST_SECRET="$SENT" FAKE_NPM_LOG="$NPMLOG" FAKE_AB_LOG="$ABLOG" \
     ${extra[@]+"${extra[@]}"} bash "$SB" "$@") >"$TMP/out" 2>"$TMP/err"
  RC=$?; OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
  cat "$TMP/out" "$TMP/err" >> "$ALLOUT"
}
npm_calls() { grep -c . "$NPMLOG" 2>/dev/null | tr -d ' '; }

P_BASE="$TOOLS:$TMP/npm:$TMP/chrome"

echo "--- поиск agent-browser"
newcache same
run "$P_BASE:$TMP/sys-same" -- --session s open https://example.com
check "system 0.43.0: rc 0" 0 "$RC"
check "system 0.43.0: npm not called" 0 "$(npm_calls)"
check "system 0.43.0: system binary ran" yes "$(contains 'WHO=system' "$(cat "$ABLOG")")"
check "system 0.43.0: no cache created" no "$([ -e "$(abdir)/0.43.0" ] && echo yes || echo no)"

newcache other
run "$P_BASE:$TMP/sys-other" -- --session s open https://example.com
check "system other version: rc 0" 0 "$RC"
check "system other version: npm called once" 1 "$(npm_calls)"
check "system other version: npm ci --ignore-scripts" yes "$(contains 'ci --ignore-scripts --no-fund --no-audit' "$(cat "$NPMLOG")")"
check "system other version: npm ran in temp dir next to cache" yes "$(contains "$(abdir)/.install-" "$(cat "$NPMLOG")")"
check "install notice line" "subteams: устанавливаю agent-browser 0.43.0 в $(abdir)/0.43.0 (один раз)" "$ERR"
check "cache binary ran (not system-old)" yes "$(contains 'WHO=cache' "$(cat "$ABLOG")")"
check "AGENT_BROWSER_SKILLS_DIR -> cache skill-data" yes "$(contains "SKILLS=$(abdir)/0.43.0/node_modules/agent-browser/skill-data" "$(cat "$ABLOG")")"
check "marker written" yes "$([ -s "$(abdir)/0.43.0/.subteams-bin" ] && echo yes || echo no)"
check "no temp dirs left" "" "$(names "$(abdir)" | grep -v -e '^0\.43\.0$' -e '^install\.log$')"
: > "$ABLOG"
run "$P_BASE:$TMP/sys-other" -- --session s snapshot -i
check "second run: cache hit, npm not called again" 1 "$(npm_calls)"
check "second run: no install notice" "" "$ERR"

newcache override
run "$P_BASE:$TMP/sys-same" CLAUDE_SUBTEAMS_AGENT_BROWSER="$TMP/override/ab" -- --session s open x
check "CLAUDE_SUBTEAMS_AGENT_BROWSER wins" yes "$(contains 'WHO=override' "$(cat "$ABLOG")")"
run "$P_BASE" CLAUDE_SUBTEAMS_AGENT_BROWSER="$TMP/nope" -- --session s open x
check "CLAUDE_SUBTEAMS_AGENT_BROWSER not executable -> 127" 127 "$RC"

newcache noauto
run "$P_BASE" CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1 -- --session s open x
check "NO_AUTO_INSTALL: 127" 127 "$RC"
check "NO_AUTO_INSTALL: npm not called" 0 "$(npm_calls)"
check "NO_AUTO_INSTALL: reason named" yes "$(contains 'CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1' "$ERR")"

newcache nonpm
run "$TOOLS:$TMP/chrome" -- --session s open x
check "no npm, nothing installed: 127" 127 "$RC"

echo "--- параллельная установка и блокировка"
newcache parallel
(cd "$CWD" && env -i HOME="$HOMEDIR" XDG_CACHE_HOME="$CACHE" PATH="$P_BASE" TMPDIR="$TMP/t" FAKE_NPM_LOG="$NPMLOG" \
   FAKE_AB_LOG="$ABLOG" FAKE_NPM_SLEEP=2 bash "$SB" --session a open x) >"$TMP/p1" 2>&1 &
p1=$!
(cd "$CWD" && env -i HOME="$HOMEDIR" XDG_CACHE_HOME="$CACHE" PATH="$P_BASE" TMPDIR="$TMP/t" FAKE_NPM_LOG="$NPMLOG" \
   FAKE_AB_LOG="$ABLOG" FAKE_NPM_SLEEP=2 bash "$SB" --session b open x) >"$TMP/p2" 2>&1 &
p2=$!
wait "$p1"; r1=$?; wait "$p2"; r2=$?
check "parallel: both rc 0" "0 0" "$r1 $r2"
check "parallel: npm exactly once" 1 "$(npm_calls)"
check "parallel: both sessions ran" 2 "$(grep -c '^WHO=cache' "$ABLOG" | tr -d ' ')"
check "parallel: lock released" no "$([ -e "$(abdir)/0.43.0.lock" ] && echo yes || echo no)"

newcache npmfail
run "$P_BASE" FAKE_NPM_FAIL=1 -- --session s open x
check "npm failed: 127" 127 "$RC"
check "npm failed: reason + log path" yes "$(contains "лог: $(abdir)/install.log" "$ERR")"
check "npm failed: no partial install" "" "$(names "$(abdir)" | grep -v '^install\.log$')"
check "npm failed: npm env not echoed" no "$(contains "$SENT" "$ERR$OUT")"
check "npm failed: agent-browser not run" "" "$(cat "$ABLOG")"

newcache stale-dead
mkdir -p "$(abdir)/0.43.0.lock"; printf '999999 %s\n' "$(( $(date +%s) - 10 ))" > "$(abdir)/0.43.0.lock/owner"
run "$P_BASE" -- --session s open x
check "stale lock (dead pid): recovered, rc 0" 0 "$RC"
check "stale lock (dead pid): npm once" 1 "$(npm_calls)"

newcache stale-old
mkdir -p "$(abdir)/0.43.0.lock"; touch -t 202001010000 "$(abdir)/0.43.0.lock"
run "$P_BASE" -- --session s open x
check "stale lock (no owner, old dir): recovered, rc 0" 0 "$RC"
check "stale lock: lock gone afterwards" no "$([ -e "$(abdir)/0.43.0.lock" ] && echo yes || echo no)"

newcache leftover
mkdir -p "$(abdir)/.install-old1" && touch -t 202001010000 "$(abdir)/.install-old1"
run "$P_BASE" -- --session s open x
check "leftover temp dir of a killed install swept" no "$([ -e "$(abdir)/.install-old1" ] && echo yes || echo no)"

# таймаут npm ci: копия обёртки с таймаутом 2 с вместо 120 (рядом — те же deps/)
mkdir -p "$TMP/plug/bin"; ln -s "$(dirname "$(dirname "$SB")")/deps" "$TMP/plug/deps"
sed 's/^INSTALL_TIMEOUT=120 /INSTALL_TIMEOUT=2 /' "$SB" > "$TMP/plug/bin/subteams-browser"; chmod +x "$TMP/plug/bin/subteams-browser"
check "timeout copy prepared" 1 "$(grep -c '^INSTALL_TIMEOUT=2 ' "$TMP/plug/bin/subteams-browser")"
newcache timeout
SB_SAVED="$SB"; SB="$TMP/plug/bin/subteams-browser"
t0=$(date +%s)
run "$P_BASE" FAKE_NPM_SLEEP=37.123 FAKE_NPM_IGNORE_TERM=1 -- --session s open x
t1=$(date +%s)
SB="$SB_SAVED"
check "npm ci timeout: npm deaf to TERM is KILLed, not waited out (<15 s)" yes "$([ $((t1 - t0)) -lt 15 ] && echo yes || echo "no ($((t1 - t0)) s)")"
check "npm ci timeout: 127" 127 "$RC"
check "npm ci timeout: reason named" yes "$(contains 'не уложился в 2 с' "$ERR")"
check "npm ci timeout: no partial install, no lock" "" "$(names "$(abdir)" | grep -v '^install\.log$')"
check "npm ci timeout: npm process gone" no "$(pgrep -f "^bash $TMP/npm/npm ci" >/dev/null && echo yes || echo no)"
check "npm ci timeout: npm child (sleep) gone" no "$(pgrep -f '^sleep 37[.]123$' >/dev/null && echo yes || echo no)"

newcache wrongver
run "$P_BASE" FAKE_INSTALL_VER=0.42.0 -- --session s open x
check "installed binary wrong version: 127" 127 "$RC"
check "wrong version: reason named" yes "$(contains 'версия не 0.43.0' "$ERR")"
check "wrong version: nothing left in cache" "" "$(names "$(abdir)" | grep -v '^install\.log$')"

newcache broken
mkdir -p "$(abdir)/0.43.0/node_modules"   # установка без маркера = битая
run "$P_BASE" -- --session s open x
check "broken cache (no marker): reinstalled, rc 0" 0 "$RC"
check "broken cache: npm once" 1 "$(npm_calls)"

echo "--- сессия и аргументы"
newcache args
run "$P_BASE:$TMP/sys-same" -- open https://example.com
check "no --session: exit 2" 2 "$RC"
check "no --session: agent-browser not run" "" "$(cat "$ABLOG")"
run "$P_BASE:$TMP/sys-same" -- open https://example.com --session
check "--session without value: exit 2" 2 "$RC"
run "$P_BASE:$TMP/sys-same" -- --session=s open x
check "--session=name form: exit 2" 2 "$RC"
run "$P_BASE:$TMP/sys-same" AGENT_BROWSER_SESSION=s -- open x
check "AGENT_BROWSER_SESSION env does not replace --session: exit 2" 2 "$RC"
: > "$ABLOG"
# shellcheck disable=SC2016  # буквальные $ и ` — часть проверки
weird='a b "c" '\''d'\'' $HOME `x` \n *'
run "$P_BASE:$TMP/sys-same" -- --session s fill @e1 "$weird" ''
check "args verbatim: rc 0" 0 "$RC"
check "args verbatim: argc (incl. empty)" "ARGC=6" "$(grep '^ARGC=' "$ABLOG")"
check "args verbatim: spaces/quotes intact" "[$weird]" "$(sed -n '7p' "$ABLOG")"
check "args verbatim: empty arg kept" "[]" "$(sed -n '8p' "$ABLOG")"
for ex in --version --help skills; do
  : > "$ABLOG"
  run "$P_BASE:$TMP/sys-same" -- "$ex" list
  check "no session needed: $ex" 0 "$RC"
done
: > "$ABLOG"
run "$TOOLS:$TMP/sys-same" -- --version
check "--version without browser: rc 0" 0 "$RC"
: > "$ABLOG"
run "$P_BASE:$TMP/sys-same" -- setup
check "setup: runs agent-browser install" yes "$(contains '[install]' "$(cat "$ABLOG")")"

echo "--- запреты"
deny() { # <имя> <ожидаемый фрагмент текста> <аргументы…>
  local name="$1" frag="$2"; shift 2
  : > "$ABLOG"
  run "$P_BASE:$TMP/sys-same" -- "$@"
  check "deny $name: exit 2" 2 "$RC"
  check "deny $name: reason" yes "$(contains "$frag" "$ERR")"
  check "deny $name: agent-browser not run" "" "$(cat "$ABLOG")"
}
deny "install" 'subteams-browser setup' --session s install
deny "install --with-deps" 'subteams-browser setup' --session s install --with-deps
deny "install without session" 'subteams-browser setup' install
deny "upgrade" 'закреплена плагином' --session s upgrade
deny "close --all" 'только свою сессию' --session s close --all
deny "close --all (flag first)" 'только свою сессию' --all --session s close
deny "--executable-path" 'AGENT_BROWSER_EXECUTABLE_PATH' --session s --executable-path "$TMP/chrome/google-chrome" open x
deny "--executable-path=" 'не использовать' --session s open x --executable-path=/x/chrome
: > "$ABLOG"
run "$P_BASE:$TMP/sys-same" -- --session s close
check "plain close of own session allowed" "0 yes" "$RC $(contains '[close]' "$(cat "$ABLOG")")"
run "$TOOLS:$TMP/npm:$TMP/sys-same" -- --session s --cdp 9222 open x
check "--cdp still skips the browser check" 0 "$RC"

echo "--- браузер"
newcache nobrowser
mac_chrome=no
if [ "$(uname -s)" = Darwin ]; then
  for a in "/Applications/Google Chrome.app" "/Applications/Chromium.app"; do [ -d "$a" ] && mac_chrome=yes; done
fi
if [ "$mac_chrome" = yes ]; then echo "SKIP no-browser cases: Chrome in /Applications on this Mac"; else
run "$TOOLS:$TMP/npm:$TMP/sys-same" -- --session s open x
check "no browser: 127" 127 "$RC"
check "no browser: hint subteams-browser setup" yes "$(contains 'subteams-browser setup' "$ERR")"
check "no browser: agent-browser not run" "" "$(cat "$ABLOG")"
check "no browser: npm not called" 0 "$(npm_calls)"
mkdir -p "$HOMEDIR/.agent-browser/browsers/chrome-x"
run "$TOOLS:$TMP/npm:$TMP/sys-same" -- --session s open x
check "Chrome from setup (~/.agent-browser/browsers): rc 0" 0 "$RC"
rm -rf "$HOMEDIR/.agent-browser"
run "$TOOLS:$TMP/npm:$TMP/sys-same" AGENT_BROWSER_EXECUTABLE_PATH="$TMP/chrome/google-chrome" -- --session s open x
check "AGENT_BROWSER_EXECUTABLE_PATH: rc 0" 0 "$RC"
mkdir -p "$HOMEDIR/.cache/ms-playwright/chromium-1"
run "$TOOLS:$TMP/npm:$TMP/sys-same" -- --session s open x
check "Playwright Chromium is not counted: 127" 127 "$RC"
rm -rf "$HOMEDIR/.cache"
fi

echo "--- квитанция shot"
newcache shot
REPO="$TMP/repo"; mkdir -p "$REPO" && git -C "$REPO" init -q -b main && git -C "$REPO" commit -q --allow-empty -m base
CANON=$(cd -P "$REPO/.git" && pwd)
if command -v sha1sum >/dev/null 2>&1; then RID=$(printf '%s' "$CANON" | sha1sum | cut -d' ' -f1)
else RID=$(printf '%s' "$CANON" | shasum -a 1 | cut -d' ' -f1); fi
RDIR="$CACHE/claude-subteams/receipts/$RID"
mkdir -p "$TMP/shots"
CWD="$REPO/"
run "$P_BASE:$TMP/sys-same" -- --session ui-1 screenshot "$TMP/shots/a \"b\".png"
check "screenshot: rc 0" 0 "$RC"
nrec=$(names "$RDIR" | grep -c '^shot-.*\.json$' | tr -d ' ')
check "screenshot: one shot receipt in repo store" 1 "$nrec"
rec=$(cat "$RDIR"/shot-*.json 2>/dev/null)
got=$(printf '%s' "$rec" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log([j.type,j.kind,j.path,j.size,j.session,typeof j.ts,j.root].join("|"))})' 2>&1)
check "screenshot: receipt fields (type + kind + root)" "shot|shot|$TMP/shots/a \"b\".png|7|ui-1|number|$(cd -P "$REPO" && pwd)" "$got"
check "screenshot: no temp files in store" "" "$(names "$RDIR" | grep -v '^shot-.*\.json$')"
git -C "$REPO" worktree add -q "$TMP/wt" -b wt 2>/dev/null
CWD="$TMP/wt"
run "$P_BASE:$TMP/sys-same" -- --session ui-1 screenshot --full "$TMP/shots/w.png"
check "screenshot from worktree: same repo store" 2 "$(names "$RDIR" | grep -c '^shot-' | tr -d ' ')"
check "screenshot from worktree: root = the worktree" 1 "$(cat "$RDIR"/shot-*.json | grep -c "\"root\":\"$(cd -P "$TMP/wt" && pwd)\"")"
CWD="$REPO"
run "$P_BASE:$TMP/sys-same" FAKE_AB_RC=1 -- --session ui-1 screenshot "$TMP/shots/fail.png"
check "screenshot failed: rc passed through" 1 "$RC"
check "screenshot failed: no receipt" 2 "$(names "$RDIR" | grep -c '^shot-' | tr -d ' ')"
run "$P_BASE:$TMP/sys-same" -- --session ui-1 screenshot
check "screenshot without path: rc 0, no receipt" "0 2" "$RC $(names "$RDIR" | grep -c '^shot-' | tr -d ' ')"
check "screenshot without receipt in a repo: hint to pass an absolute path" yes "$(contains 'абсолютный путь' "$ERR")"
printf 'OLDJPG' > "$TMP/shots/old.jpg"; touch -t 202001010000 "$TMP/shots/old.jpg"
run "$P_BASE:$TMP/sys-same" -- --session ui-1 screenshot "$TMP/shots/old.jpg"
check "screenshot rc 0 but file not rewritten (stale): no receipt" "0 2" "$RC $(names "$RDIR" | grep -c '^shot-' | tr -d ' ')"
touch -t 202001010000 "$RDIR/old.json"
run "$P_BASE:$TMP/sys-same" -- --session ui-1 screenshot "$TMP/shots/c.png"
check "receipts older than 14 days pruned on write" no "$([ -e "$RDIR/old.json" ] && echo yes || echo no)"
CWD="$TMP/shots"
before=$(find "$CACHE/claude-subteams/receipts" -type f | wc -l | tr -d ' ')
run "$P_BASE:$TMP/sys-same" -- --session ui-1 screenshot "$TMP/shots/d.png"
check "screenshot outside git: rc 0, no receipt" "0 $before" "$RC $(find "$CACHE/claude-subteams/receipts" -type f | wc -l | tr -d ' ')"
check "screenshot outside git: silent" "" "$ERR"
CWD="$TMP"

echo "--- окружение"
check "environment never printed (sentinel absent in all output)" no "$(grep -q "$SENT" "$ALLOUT" && echo yes || echo no)"

echo
echo "SUMMARY: $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ]
