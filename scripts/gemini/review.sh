#!/usr/bin/env bash
# review.sh — прямой вызов Gemini-ревью (третья модель кросс-ревью) без LLM-прослойки.
# Использование: review.sh [BASE_REF] [-o OUTFILE]
#   BASE_REF  база диффа (дефолт main); дифф берётся: git diff --merge-base BASE_REF
#   -o        писать JSON находок в файл (иначе stdout)
# Запускать из корня ревьюируемого репо. Выходные коды как у agy-run.sh + 5 (пустой/битый дифф).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="main"; OUTFLAG=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) [ "$#" -ge 2 ] || { echo "review.sh: у -o нет аргумента" >&2; exit 5; }
        OUTFLAG=(-o "$2"); shift 2 ;;
    *)  BASE="$1"; shift ;;
  esac
done

DIFF_FILE=$(mktemp /tmp/gemini-review-diff-XXXXXX.patch)
trap 'rm -f "$DIFF_FILE"' EXIT
if ! git diff --merge-base "$BASE" > "$DIFF_FILE" 2>/dev/null; then
  echo "review.sh: git diff не собрался (плохой base ref \"$BASE\"?)" >&2; exit 5
fi
[ -s "$DIFF_FILE" ] || { echo "review.sh: дифф пуст — ревьюировать нечего" >&2; exit 5; }
echo "review.sh: дифф $(wc -l <"$DIFF_FILE") строк (base $BASE)" >&2

PROMPT="You are a senior code reviewer providing a third-model opinion. A Claude-family review has already run, and GPT critics may have run too. Use ONLY your read_file tool (terminal commands are forbidden) to read the git diff at: $DIFF_FILE

Review it for material defects. Priority classes commonly under-weighted by other model families — start here, but report ANYTHING material: (1) subtle concurrency/ordering bugs; (2) numeric/precision hazards incl. money-in-floats; (3) platform/locale edge cases; (4) spec-vs-implementation drift on boundary/empty/null inputs; (5) security footguns (injection, SSRF, ReDoS, path traversal, insecure randomness); (6) resource lifecycle bugs.

Return ONLY a valid JSON object — no markdown fences, no prose:
{\"findings\":[{\"severity\":\"critical|high|medium|low\",\"file\":\"...\",\"line\":null,\"issue\":\"...\",\"why_others_might_miss\":\"...\"}],\"summary\":\"...\"}"

printf '%s' "$PROMPT" | "$DIR/agy-run.sh" -m pro -j -t 330 "${OUTFLAG[@]}"
