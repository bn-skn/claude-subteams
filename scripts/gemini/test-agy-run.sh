#!/usr/bin/env bash
# test-agy-run.sh — регрессия автоопределения модели в agy-run.sh (-m pro / -r).
# Подменный `agy` во временном каталоге стоит первым в PATH; дочерний bash запускается через
# `env -u BASH_ENV`: на этой машине BASH_ENV кладёт ~/.local/bin (настоящий agy) в начало PATH в каждом child bash.
# Использование: bash scripts/gemini/test-agy-run.sh   (exit 0 = все PASS, иначе 1)
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$DIR/agy-run.sh"
TMP=$(mktemp -d /tmp/test-agy-run-XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

cat > "$TMP/bin/agy" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = models ]; then cat "$STUB_MODELS"; exit 0; fi
printf '%s\n' "$*" >> "$STUB_LOG"
echo OK
STUB
chmod +x "$TMP/bin/agy"

T=$'\t'
FAILS=0
# row <slug> <label> — строка листинга agy 1.4.9 (две колонки через TAB)
row() { printf '%s\t%s\n' "$1" "$2"; }

REAL=$(printf 'Fetching available models...\n'
  row gemini-3.8-flash-high "Gemini 3.8 Flash (High)"
  row gemini-3.8-flash-medium "Gemini 3.8 Flash (Medium)"
  row gemini-3.8-flash-low "Gemini 3.8 Flash (Low)"
  row claude-sonnet-4-6 "Claude Sonnet 4.6 (Thinking)"
  row claude-opus-4-6-thinking "Claude Opus 4.6 (Thinking)"
  row gpt-oss-120b-medium "GPT-OSS 120B (Medium)")

# resolve <listing> [VAR=val ...] -> stdout "<label>|rc"
resolve() {
  local listing="$1"; shift
  printf '%s\n' "$listing" > "$TMP/listing.txt"
  local out rc
  out=$(env -u BASH_ENV PATH="$TMP/bin:$PATH" STUB_MODELS="$TMP/listing.txt" "$@" bash "$RUN" -r 2>/dev/null); rc=$?
  printf '%s|%s' "$out" "$rc"
}

check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAILS=$((FAILS+1)); fi
}

# (a) реальный листинг: единственная Gemini — Flash 3.8
check "a real listing" "Gemini 3.8 Flash (High)|0" "$(resolve "$REAL")"

# (b) Pro старой версии бьёт более новый Flash (tier-first)
check "b Pro beats newer Flash" "Gemini 3.1 Pro (Low)|0" "$(resolve "$(printf '%s\n' "$REAL"; row gemini-3.1-pro-low "Gemini 3.1 Pro (Low)")")"

# (c) версия сравнивается как число: 3.10 > 3.2 > 3.1 (лексикографически победил бы 3.2)
check "c 3.10 beats 3.2 and 3.1" "Gemini 3.10 Pro (High)|0" "$(resolve "$(row a "Gemini 3.1 Pro (High)"; row b "Gemini 3.10 Pro (High)"; row c "Gemini 3.2 Pro (High)")")"

# (d) только слаги (нет TAB-колонки) -> пусто + exit 3
check "d slug-only -> empty, exit 3" "|3" "$(resolve "$(printf 'Fetching available models...\ngemini-3.8-flash-high\ngemini-3.1-pro-high\nclaude-sonnet-4-6\n')")"

# (e) override
check "e GEMINI_PRO_MODEL override" "Custom X (High)|0" "$(resolve "$REAL" GEMINI_PRO_MODEL="Custom X (High)")"

# (f) tie-cases: лишние слова в имени не должны выигрывать, в любом порядке строк
for extra in "Flash Lite" "Flash-Lite" "Flash Image"; do
  check "f Flash beats '$extra' (extra first)" "Gemini 3.8 Flash (High)|0" "$(resolve "$(row x "Gemini 3.8 $extra (High)"; row y "Gemini 3.8 Flash (High)")")"
  check "f Flash beats '$extra' (extra last)"  "Gemini 3.8 Flash (High)|0" "$(resolve "$(row y "Gemini 3.8 Flash (High)"; row x "Gemini 3.8 $extra (High)")")"
done
check "f Pro beats 'Pro Deep Think' (extra first)" "Gemini 3.1 Pro (High)|0" "$(resolve "$(row x "Gemini 3.1 Pro Deep Think (High)"; row y "Gemini 3.1 Pro (High)")")"
check "f Pro beats 'Pro Deep Think' (extra last)"  "Gemini 3.1 Pro (High)|0" "$(resolve "$(row y "Gemini 3.1 Pro (High)"; row x "Gemini 3.1 Pro Deep Think (High)")")"
# Flash Lite новее Flash не должен выигрывать по версии: tier главнее
check "f older Flash beats newer 'Flash Lite'" "Gemini 3.8 Flash (High)|0" "$(resolve "$(row x "Gemini 3.9 Flash Lite (High)"; row y "Gemini 3.8 Flash (High)")")"

# (g) CRLF: в ответе нет \r и effort разобран как High (а не Medium из-за "(High)\r")
CRLF_OUT=$(resolve "$(printf '%s\r\n' "Fetching available models..." "gemini-3.8-flash-medium${T}Gemini 3.8 Flash (Medium)" "gemini-3.8-flash-high${T}Gemini 3.8 Flash (High)")")
check "g CRLF listing" "Gemini 3.8 Flash (High)|0" "$CRLF_OUT"
case "$CRLF_OUT" in *$'\r'*) echo "FAIL g CRLF: CR in output"; FAILS=$((FAILS+1));; esac

# (h) полный прогон -m pro со слаг-листингом: argv без --model, DEGRADED в stderr
printf 'Fetching available models...\ngemini-3.8-flash-high\n' > "$TMP/listing.txt"
rm -f "$TMP/argv.log"
H_ERR=$(echo hi | env -u BASH_ENV PATH="$TMP/bin:$PATH" STUB_MODELS="$TMP/listing.txt" STUB_LOG="$TMP/argv.log" bash "$RUN" -m pro 2>&1 >/dev/null); H_RC=$?
check "h full run rc" "0" "$H_RC"
case "$H_ERR" in *"agy-run: DEGRADED — не удалось автоопределить сильнейшую Gemini, работаю на дефолте settings.json"*) echo "PASS h DEGRADED line on stderr";; *) echo "FAIL h DEGRADED line missing: $H_ERR"; FAILS=$((FAILS+1));; esac
case "$(cat "$TMP/argv.log" 2>/dev/null)" in *--model*) echo "FAIL h argv contains --model: $(cat "$TMP/argv.log")"; FAILS=$((FAILS+1));; "") echo "FAIL h agy never called"; FAILS=$((FAILS+1));; *) echo "PASS h argv has no --model";; esac

if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAIL"; exit 1; fi
