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
         dirname basename readlink wc tr cut sed ls pkill chmod touch grep head node stat; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -s "$p" "$TOOLS/$t"
done
[ -e "$TOOLS/node" ] || { echo "node required"; exit 2; }
[ -e "$TOOLS/git" ] || { echo "git required"; exit 2; }

# --- подделки ----------------------------------------------------------------
mkfake_ab() { # <путь> <версия> <метка>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = --version ]; then printf 'VERSION_CALL=%s\n' "$3" >> "\${FAKE_AB_VLOG:-/dev/null}"; echo "agent-browser $2"; exit 0; fi
log="\${FAKE_AB_LOG:-/dev/null}"
{ printf 'WHO=%s\n' "$3"; printf 'ARGC=%s\n' "\$#"; for a in "\$@"; do printf '[%s]\n' "\$a"; done
  printf 'SKILLS=%s\n' "\${AGENT_BROWSER_SKILLS_DIR:-}"; printf 'UMASK=%s\n' "\$(umask)"; env | grep '^AGENT_BROWSER_' | sed 's/^/ENV:/'; } >> "\$log"
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
printf 'node_modules\n' > npm-made.txt   # файл, созданный «npm» с умаском обёртки
src="$TMP/fake-installed-ab"; [ "\${FAKE_INSTALL_VER:-0.43.0}" = 0.43.0 ] || src="$TMP/fake-installed-ab-old"
for p in cli-linux-x64-gnu cli-linux-x64-musl cli-linux-arm64-gnu cli-linux-arm64-musl cli-darwin-x64 cli-darwin-arm64; do
  case "\$p" in *-gnu) [ "\${FAKE_NPM_SKIP_GNU:-0}" = 1 ] && continue ;; esac   # npm пропустил optional-пакет
  mkdir -p "node_modules/@agent-browser/\$p/bin"; cp "\$src" "node_modules/@agent-browser/\$p/bin/agent-browser"
done
[ "\${FAKE_NPM_FAIL:-0}" = 1 ] && { echo "npm ERR! simulated" >&2; exit 1; }
exit 0
EOF
chmod +x "$TMP/npm/npm"

HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR" "$TMP/t"
NPMLOG="$TMP/npm.log"; ABLOG="$TMP/ab.log"; VLOG="$TMP/version.log"; ALLOUT="$TMP/all-output"
: > "$ALLOUT"

CACHE=""; CWD="$TMP"
newcache() { CACHE="$TMP/cache-$1"; mkdir -p "$CACHE"; : > "$NPMLOG"; : > "$ABLOG"; : > "$VLOG"; }
abdir() { echo "$CACHE/claude-subteams/agent-browser"; }

RC=0; OUT=""; ERR=""
# run <PATH> [VAR=val ...] -- <аргументы subteams-browser>
run() {
  local path="$1"; shift
  local -a extra=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do extra+=("$1"); shift; done
  shift
  (cd "$CWD" && umask 022 && env -i HOME="$HOMEDIR" XDG_CACHE_HOME="$CACHE" PATH="$path" TMPDIR="$TMP/t" \
     SUBTEAMS_TEST_SECRET="$SENT" FAKE_NPM_LOG="$NPMLOG" FAKE_AB_LOG="$ABLOG" FAKE_AB_VLOG="$VLOG" \
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
check "install notice line" "subteams: installing agent-browser 0.43.0 into $(abdir)/0.43.0 (one time)" "$ERR"
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
check "npm failed: reason + log path" yes "$(contains "log: $(abdir)/install.log" "$ERR")"
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

# таймаут npm ci: копия обёртки с таймаутом 2 с вместо 90 (рядом — те же deps/)
mkdir -p "$TMP/plug/bin"; ln -s "$(dirname "$(dirname "$SB")")/deps" "$TMP/plug/deps"
sed 's/^INSTALL_TIMEOUT=90 /INSTALL_TIMEOUT=2 /' "$SB" > "$TMP/plug/bin/subteams-browser"; chmod +x "$TMP/plug/bin/subteams-browser"
check "timeout copy prepared" 1 "$(grep -c '^INSTALL_TIMEOUT=2 ' "$TMP/plug/bin/subteams-browser")"
newcache timeout
SB_SAVED="$SB"; SB="$TMP/plug/bin/subteams-browser"
t0=$(date +%s)
run "$P_BASE" FAKE_NPM_SLEEP=37.123 FAKE_NPM_IGNORE_TERM=1 -- --session s open x
t1=$(date +%s)
SB="$SB_SAVED"
check "npm ci timeout: npm deaf to TERM is KILLed, not waited out (<15 s)" yes "$([ $((t1 - t0)) -lt 15 ] && echo yes || echo "no ($((t1 - t0)) s)")"
check "npm ci timeout: 127" 127 "$RC"
check "npm ci timeout: reason named" yes "$(contains 'did not finish within 2 s' "$ERR")"
check "npm ci timeout: no partial install, no lock" "" "$(names "$(abdir)" | grep -v '^install\.log$')"
check "npm ci timeout: npm process gone" no "$(pgrep -f "^bash $TMP/npm/npm ci" >/dev/null && echo yes || echo no)"
check "npm ci timeout: npm child (sleep) gone" no "$(pgrep -f '^sleep 37[.]123$' >/dev/null && echo yes || echo no)"

newcache wrongver
run "$P_BASE" FAKE_INSTALL_VER=0.42.0 -- --session s open x
check "installed binary wrong version: 127" 127 "$RC"
check "wrong version: reason named" yes "$(contains 'version is not 0.43.0' "$ERR")"
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
for ex in --version -V --help -h "skills list" "skills get --all" "session list"; do
  : > "$ABLOG"
  # shellcheck disable=SC2086  # намеренное разбиение «skills list» на слова
  run "$P_BASE:$TMP/sys-same" -- $ex
  check "no session needed: $ex" "0 yes" "$RC $([ -s "$ABLOG" ] || [ "${ex#-}" != "$ex" ] && echo yes || echo no)"
done
: > "$ABLOG"
run "$TOOLS:$TMP/sys-same" -- --version
check "--version without browser: rc 0" 0 "$RC"
: > "$ABLOG"
run "$P_BASE:$TMP/sys-same" -- setup
check "setup: runs agent-browser install" yes "$(contains '[install]' "$(cat "$ABLOG")")"
: > "$ABLOG"
run "$P_BASE:$TMP/sys-same" -- setup --with-deps
check "setup --with-deps: passed to install" "0 yes" "$RC $(contains '[--with-deps]' "$(cat "$ABLOG")")"

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
deny "upgrade" 'pinned by the plugin' --session s upgrade
deny "close --all" 'only your own session' --session s close --all
deny "close --all (flag first)" 'not allowed before the command' --all --session s close
deny "--executable-path" 'AGENT_BROWSER_EXECUTABLE_PATH' --session s --executable-path "$TMP/chrome/google-chrome" open x
deny "--executable-path=" 'no-sandbox' --session s open x --executable-path=/x/chrome
# обход старого denylist: значение глобальной опции принималось за команду
deny "value option hides install" 'subteams-browser setup' --session s --user-agent x install
deny "value option hides upgrade" 'pinned by the plugin' --user-agent x --session s upgrade
deny "unknown option before command" 'not allowed before the command' --foo v --session s close --all
deny "unknown option, value looks like a command" 'not allowed before the command' --session s --sess open x
deny "--opt=value before command" 'not allowed before the command' --session s --json=true open x
deny "bool option eats only true/false" 'subteams-browser setup' --session s --json install
deny "bool option + false, then install" 'subteams-browser setup' --session s --hide-scrollbars false install
deny "--version with a command" 'not allowed before the command' --version install
deny "setup with extra args" 'other than --with-deps' setup --force
deny "setup with a denied flag" 'other than --with-deps' setup --profile Default
for c in plugin auth dashboard connect doctor profiles cookies storage network trace profiler batch chat mcp \
         state stream webmcp flow react vitals a11y pushstate removeinitscript confirm deny diff pdf read \
         keyboard mouse drag upload highlight inspect clipboard quit exit help; do
  deny "command $c" "command '$c' is not allowed" --session s "$c" x
done
deny "state save" "command 'state'" --session s state save /tmp/auth.json
deny "network route" "command 'network'" --session s network route '*' --abort
deny "set credentials" "'set credentials' is not allowed" --session s set credentials u p
deny "set headers" "'set headers' is not allowed" --session s set headers '{}'
deny "set geo" "'set geo' is not allowed" --session s set geo 1 2
deny "set, option in subcommand slot" "is not allowed; allowed: set" --session s set --foo viewport 1 2
deny "session info" "'session info' is not allowed" --session s session info
deny "bare session" "'session ' is not allowed" session
deny "skills path" "'skills path' is not allowed" skills path
deny "record without start/stop" "'record ' is not allowed" --session s record
deny "wait --download" 'arbitrary path' --session s wait --download /home/x/.bashrc
for f in --profile --auto-connect --cdp --cdp-headers --args --config --extension --init-script --init-scripts \
         --allow-file-access --user-data-dir --state --restore --restore-save --restore-check-url \
         --restore-check-text --restore-check-fn --session-name -p --provider --engine --ca-cert --download-path; do
  deny "flag $f before command" "option $f is not allowed" --session s "$f" x open y
  deny "flag $f after command" "option $f is not allowed" --session s open y "$f" x
done
deny "flag --profile=Default" 'option --profile is not allowed' --session s open y --profile=Default
deny "flag hidden as a value (fail closed)" 'option --profile is not allowed' --session s --user-agent --profile open y
deny "--headed" 'headless' --session s --headed open y
deny "--state before wait" 'option --state is not allowed' --session s --state /x/auth.json wait 100
deny "no command" 'no command given' --session s
: > "$ABLOG"
run "$P_BASE:$TMP/sys-same" -- --session s close
check "plain close of own session allowed" "0 yes" "$RC $(contains '[close]' "$(cat "$ABLOG")")"
run "$TOOLS:$TMP/npm:$TMP/sys-same" -- --session s --cdp 9222 open x
check "--cdp denied even without a browser" 2 "$RC"

echo "--- разрешённое"
allow() { # <имя> <аргументы…>
  local name="$1"; shift
  : > "$ABLOG"
  run "$P_BASE:$TMP/sys-same" -- "$@"
  check "allow $name: rc 0, agent-browser ran" "0 yes" "$RC $([ -s "$ABLOG" ] && echo yes || echo no)"
}
for c in open snapshot click dblclick fill type press hover focus select check uncheck scroll scrollintoview \
         wait get is find eval console errors tab back forward reload; do
  allow "$c" --session s "$c" x
done
allow "set viewport 320" --session s set viewport 320 800
allow "set device" --session s set device "iPhone 12"
allow "set media" --session s set media dark
allow "record start" --session s record start "$TMP/v.webm"
allow "record stop" --session s record stop
allow "tab new" --session s tab new https://example.com
allow "global value option before command" --user-agent x --session s open y
allow "bool option + true" --json true --session s snapshot -i
allow "hide-scrollbars false" --hide-scrollbars false --session s screenshot
allow "wait --state (selector state)" --session s wait "#x" --state hidden
allow "skills get --all (--all not denied outside close)" skills get --all
deny "--session after the command" 'must come before the command' open y --session s
deny "--session after -- (agent-browser stops parsing there)" 'must come before the command' open y -- --session s
deny "--session swallowed by an unlisted value option" 'must come before the command' open y --proxy --session s
deny "second --session after the command" 'must come before the command' --session s open y --session t
deny "wait --state with a file path" 'option --state is not allowed' --session s wait 100 --state /x/auth.json
deny "--state <selector-state word> after a non-wait command" 'option --state is not allowed' --session s open y --state hidden
for st in visible hidden attached detached; do allow "wait --state $st" --session s wait "#x" --state "$st"; done

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
check "screenshot without receipt in a repo: hint to pass an absolute path" yes "$(contains 'pass an absolute path' "$ERR")"
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

echo "--- маркер кэша и повторная проверка версии"
newcache marker
run "$P_BASE" -- --session s open x
check "marker: initial install rc 0" 0 "$RC"
INST="$(abdir)/0.43.0"; REL=$(cat "$INST/.subteams-bin")
check "marker: verified stamp written at install" yes "$([ -s "$INST/.subteams-verified" ] && echo yes || echo no)"
: > "$ABLOG"; : > "$VLOG"
run "$P_BASE" CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1 -- --session s open x
check "cache launch: rc 0, cache binary" "0 yes" "$RC $(contains 'WHO=cache' "$(cat "$ABLOG")")"
check "cache launch: version check cached (no --version call)" "" "$(cat "$VLOG")"
touch -t 202001010000 "$INST/$REL"
run "$P_BASE" CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1 -- --session s open x
check "binary mtime changed: version re-checked once" "VERSION_CALL=cache" "$(cat "$VLOG")"
run "$P_BASE" CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1 -- --session s open x
check "re-check cached again for the new mtime" "VERSION_CALL=cache" "$(cat "$VLOG")"
cp "$TMP/fake-installed-ab-old" "$INST/$REL"
: > "$ABLOG"
run "$P_BASE" CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1 -- --session s open x
check "cached binary swapped for 0.42.0: not run, 127" "127 no" "$RC $(contains 'WHO=cache-old' "$(cat "$ABLOG")")"
run "$P_BASE" -- --session s open x
check "swapped binary: reinstalled, rc 0" "0 yes" "$RC $(contains 'WHO=cache' "$(grep -v cache-old "$ABLOG")")"
mkfake_ab "$INST/evil" 0.43.0 evil
for bad in evil /bin/sh "$INST/evil" "../0.43.0/evil" "$REL/../../../../../evil" "$(printf '%s\nevil' "$REL")"; do
  printf '%s\n' "$bad" > "$INST/.subteams-bin"
  : > "$ABLOG"
  run "$P_BASE" CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1 -- --session s open x
  check "marker not a platform candidate [$(printf '%s' "$bad" | tr '\n' '|')]: not run, 127" "127 no" "$RC $(contains 'WHO=evil' "$(cat "$ABLOG")")"
done

echo "--- окружение agent-browser"
newcache env
: > "$ABLOG"
run "$P_BASE:$TMP/sys-same" AGENT_BROWSER_ARGS=--no-sandbox AGENT_BROWSER_CONFIG=/x AGENT_BROWSER_PROFILE=Default \
    AGENT_BROWSER_INIT_SCRIPTS=/x AGENT_BROWSER_EXTENSIONS=/x AGENT_BROWSER_CDP=9222 AGENT_BROWSER_CDP_HEADERS=x \
    AGENT_BROWSER_AUTO_CONNECT=1 AGENT_BROWSER_PLUGINS='{}' AGENT_BROWSER_ALLOW_FILE_ACCESS=1 AGENT_BROWSER_PROVIDER=x \
    AGENT_BROWSER_ENGINE=lightpanda AGENT_BROWSER_STATE=/x AGENT_BROWSER_RESTORE=x AGENT_BROWSER_RESTORE_SAVE=always \
    AGENT_BROWSER_SESSION_NAME=x AGENT_BROWSER_HEADED=1 AGENT_BROWSER_DOWNLOAD_PATH=/x AGENT_BROWSER_CA_CERT=/x \
    AGENT_BROWSER_EXECUTABLE_PATH="$TMP/chrome/google-chrome" AGENT_BROWSER_COLOR_SCHEME=dark -- --session s open x
check "env: rc 0" 0 "$RC"
check "env: dangerous AGENT_BROWSER_* scrubbed, the rest kept" \
  "ENV:AGENT_BROWSER_COLOR_SCHEME=dark|ENV:AGENT_BROWSER_EXECUTABLE_PATH=$TMP/chrome/google-chrome" \
  "$(grep '^ENV:' "$ABLOG" | sort | paste -sd'|' -)"
mkdir -p "$TMP/pw/ms-playwright/chromium-1/chrome-linux"
printf '#!/bin/sh\nexit 0\n' > "$TMP/pw/ms-playwright/chromium-1/chrome-linux/chrome"; chmod +x "$TMP/pw/ms-playwright/chromium-1/chrome-linux/chrome"
ln -s "$TMP/pw/ms-playwright/chromium-1/chrome-linux/chrome" "$TMP/innocent-chrome"
for exe in "$TMP/pw/ms-playwright/chromium-1/chrome-linux/chrome" "$TMP/innocent-chrome"; do
  : > "$ABLOG"
  run "$P_BASE:$TMP/sys-same" AGENT_BROWSER_EXECUTABLE_PATH="$exe" -- --session s open x
  check "AGENT_BROWSER_EXECUTABLE_PATH into ms-playwright refused ($(basename "$exe")): 2, not run" "2 yes " \
    "$RC $(contains 'Playwright' "$ERR") $(cat "$ABLOG")"
done

echo "--- права и XDG_CACHE_HOME"
newcache perms
run "$P_BASE" -- --session s open x
check "umask: install rc 0" 0 "$RC"
check "umask 077: nothing the wrapper created is group/other accessible" "" \
  "$(find "$CACHE/claude-subteams" -perm -g=r -o -perm -o=r -o -perm -g=x -o -perm -o=x 2>/dev/null | head -3)"
check "umask: agent-browser runs with the caller's umask" "UMASK=0022" "$(grep '^UMASK=' "$ABLOG" | sort -u)"
: > "$ABLOG"
run "$P_BASE" -- setup
check "umask: setup runs agent-browser install with the caller's umask" "UMASK=0022" "$(grep '^UMASK=' "$ABLOG" | sort -u)"
: > "$ABLOG"
run "$P_BASE" -- --session s screenshot "$TMP/umask-shot.png"
check "umask: screenshot child runs with the caller's umask" "UMASK=0022" "$(grep '^UMASK=' "$ABLOG" | sort -u)"
check "umask: npm-made file exists (control)" yes "$([ -f "$(abdir)/0.43.0/npm-made.txt" ] && echo yes || echo no)"
newcache relxdg
mkdir -p "$TMP/relcwd"; CWD="$TMP/relcwd"; rm -rf "$HOMEDIR/.cache"
run "$P_BASE" XDG_CACHE_HOME=rel/cache -- --session s open x
CWD="$TMP"
check "relative XDG_CACHE_HOME ignored: rc 0" 0 "$RC"
check "relative XDG_CACHE_HOME ignored: nothing under cwd" no "$([ -e "$TMP/relcwd/rel" ] && echo yes || echo no)"
check "relative XDG_CACHE_HOME ignored: install in \$HOME/.cache" yes "$([ -s "$HOMEDIR/.cache/claude-subteams/agent-browser/0.43.0/.subteams-bin" ] && echo yes || echo no)"
rm -rf "$HOMEDIR/.cache"

echo "--- musl вместо glibc"
if [ "$(uname -s)" = Linux ] && ! ls /lib/ld-musl-*.so.1 >/dev/null 2>&1; then
  newcache musl
  run "$P_BASE" FAKE_NPM_SKIP_GNU=1 -- --session s open x
  check "gnu package missing: musl used, rc 0" "0 yes" "$RC $(contains 'musl' "$(cat "$(abdir)/0.43.0/.subteams-bin")")"
  check "gnu package missing: one warning line" 1 "$(printf '%s\n' "$ERR" | grep -c 'using the musl build')"
  newcache gnu
  run "$P_BASE" -- --session s open x
  check "gnu package present: no musl warning" no "$(contains 'musl' "$ERR")"
else echo "SKIP musl warning: not a glibc Linux"; fi

echo "--- статические свойства"
check "INSTALL_TIMEOUT=90 (below the Bash tool's 120 s)" 1 "$(grep -c '^INSTALL_TIMEOUT=90 ' "$SB")"
check "LOCK_WAIT=100" 1 "$(grep -c '^LOCK_WAIT=100 ' "$SB")"
check "wrapper is English-only (no Cyrillic)" 0 "$(node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8");console.log((s.match(/[Ѐ-ӿ]/g)||[]).length)' "$SB")"

echo "--- окружение"
check "environment never printed (sentinel absent in all output)" no "$(grep -q "$SENT" "$ALLOUT" && echo yes || echo no)"

echo
echo "SUMMARY: $PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ]
