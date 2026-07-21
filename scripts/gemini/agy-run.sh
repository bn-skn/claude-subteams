#!/usr/bin/env bash
# agy-run.sh — программный вызов Gemini через Antigravity CLI (agy) без LLM-прослойки.
# Инкапсулирует проверенные гочи agy 1.1.5 (см. docs/SYSTEM.md 2026-07-21):
#   - --model принимает ТОЛЬКО display-label; слаги из `agy models` молча игнорируются
#   - headless soft-deny тулов: stderr `jetski: no output produced — a tool required the "X" permission`
#   - лог-верификация реальной модели по строке "Print mode: starting" СВОЕГО прогона
#   - таймауты: внешний timeout обязан быть БОЛЬШЕ --print-timeout
#
# Использование:
#   echo "промпт" | scripts/agy-run.sh [-m fast|pro|"<display label>"] [-t SEC] [-j] [-o OUTFILE]
#   scripts/agy-run.sh -m pro -j prompt.txt
#
#   -m  fast (дефолт agy из settings.json, БЕЗ --model) | pro ("Gemini 3.1 Pro (High)") | точный display-label
#   -t  внешний таймаут в секундах (дефолт 330; --print-timeout ставится на 30с меньше)
#   -j  JSON-режим: срезать одиночное ```-ограждение, провалидировать JSON (exit 4 при невалидном)
#   -o  писать ответ в файл вместо stdout
#
# Выходные коды: 0 ok · 2 agy недоступен ИЛИ ошибка использования (флаги/промпт) · 3 пустой ответ/soft-deny · 4 невалидный JSON · 124 таймаут
# Диагностика (модель, верификация, причины) — всегда в stderr, ответ — только в stdout/-o.
# Зависимость -j режима: python3 (валидация JSON); без него валидный JSON будет отвергнут с exit 4.

set -u

MODE="fast"; TIMEOUT=330; JSON=0; OUTFILE=""
while getopts "m:t:jo:" opt; do
  case "$opt" in
    m) MODE="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    j) JSON=1 ;;
    o) OUTFILE="$OPTARG" ;;
    *) echo "agy-run: неизвестный флаг" >&2; exit 2 ;;
  esac
done
shift $((OPTIND-1))

case "$TIMEOUT" in (*[!0-9]*|"") echo "agy-run: -t должен быть числом секунд" >&2; exit 2;; esac
if [ "$TIMEOUT" -le 60 ]; then echo "agy-run: -t должен быть > 60 (внешний таймаут держится выше --print-timeout)" >&2; exit 2; fi
PRINT_TO="$((TIMEOUT-30))s"

command -v agy >/dev/null || { echo "agy-run: agy не найден в PATH" >&2; exit 2; }
# </dev/null обязательно: agy съедает stdin даже в подкоманде models — иначе промпт из пайпа пропадает
agy models >/dev/null 2>&1 </dev/null || { echo "agy-run: agy models вернул ошибку (бинарник неработоспособен)" >&2; exit 2; }

MODEL_FLAG=(); WANT_LABEL=""
case "$MODE" in
  fast) : ;;  # без --model: agy возьмёт дефолт из ~/.gemini/antigravity-cli/settings.json
  pro)  WANT_LABEL="Gemini 3.1 Pro (High)"; MODEL_FLAG=(--model "$WANT_LABEL") ;;
  *)    WANT_LABEL="$MODE"; MODEL_FLAG=(--model "$WANT_LABEL") ;;
esac

# Промпт: файл-аргумент или stdin
if [ "$#" -ge 1 ]; then
  [ -r "$1" ] || { echo "agy-run: файл промпта не читается: $1" >&2; exit 2; }
  PROMPT=$(cat "$1")
else
  PROMPT=$(cat)
fi
[ -n "$PROMPT" ] || { echo "agy-run: пустой промпт" >&2; exit 2; }

OUT=$(mktemp /tmp/agy-run-out-XXXXXX.txt)
ERR=$(mktemp /tmp/agy-run-stderr-XXXXXX.log)
trap 'rm -f "$OUT" "$ERR"' EXIT

timeout "$TIMEOUT" agy "${MODEL_FLAG[@]}" --print-timeout "$PRINT_TO" -p "$PROMPT" >"$OUT" 2>"$ERR"
RC=$?

if [ "$RC" -eq 124 ]; then
  echo "agy-run: таймаут ${TIMEOUT}s" >&2; exit 124
fi

# Soft-deny: тул вне permissions.allow зарезан headless-режимом
if grep -q 'jetski: no output produced' "$ERR"; then
  PERM=$(grep -o 'required the "[^"]*" permission' "$ERR" | head -1)
  echo "agy-run: тул зарезан headless-режимом (${PERM:-permission unknown}). Ответа нет." >&2
  exit 3
fi
if [ "$RC" -ne 0 ]; then
  echo "agy-run: agy завершился с кодом $RC" >&2
  head -3 "$ERR" >&2
  exit 3
fi
if [ ! -s "$OUT" ]; then
  echo "agy-run: пустой ответ при нулевом коде (agy умер посреди генерации?)" >&2
  exit 3
fi

# Лог-верификация модели: ищем СВОЙ прогон по строке "Print mode: starting" в свежих логах.
# Логи перемешиваются при параллельных прогонах — матчим model= со своим флагом.
VERIFIED="UNVERIFIED"
if [ -n "$WANT_LABEL" ]; then
  for L in $(ls -t "$HOME"/.gemini/antigravity-cli/log/cli-*.log 2>/dev/null | head -5); do
    if grep -q "Print mode: starting.*model=\"$WANT_LABEL\"" "$L" 2>/dev/null; then
      ACTUAL=$(grep -o 'Propagating selected model override to backend: label="[^"]*"' "$L" | tail -1 | sed 's/.*label="//;s/"$//')
      if [ "$ACTUAL" = "$WANT_LABEL" ]; then VERIFIED="verified"; else VERIFIED="DEGRADED→${ACTUAL:-unknown}"; fi
      break
    fi
  done
  echo "agy-run: model=\"$WANT_LABEL\" [$VERIFIED]" >&2
else
  echo "agy-run: model=<settings default> [not checked]" >&2
fi

# JSON-режим: срезать одиночное ограждение, строгая валидация
if [ "$JSON" -eq 1 ]; then
  if head -1 "$OUT" | grep -q '^```'; then
    sed -i '1d;$d' "$OUT"
  fi
  if ! python3 -m json.tool "$OUT" >/dev/null 2>&1; then
    echo "agy-run: ответ не является валидным JSON (-j)" >&2
    exit 4
  fi
fi

if [ -n "$OUTFILE" ]; then
  cp "$OUT" "$OUTFILE"
  echo "agy-run: ответ записан в $OUTFILE ($(wc -c <"$OUTFILE") байт)" >&2
else
  cat "$OUT"
fi
exit 0
