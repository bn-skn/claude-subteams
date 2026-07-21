#!/usr/bin/env bash
# frontend.sh — прямой вызов Gemini-генератора фронтенда (конкурирующий черновик) без LLM-прослойки.
# Использование: frontend.sh BRIEF_FILE -o OUT_HTML [-t SEC]
#   BRIEF_FILE  бриф в свободной форме (тема, палитра, ограничения; кавычки безопасны)
#   -o          куда писать HTML (обязателен)
#   -t          таймаут, дефолт 630 (генерация лендинга ~5 мин)
# Выходные коды как у agy-run.sh + 5 (вход/выход не заданы) + 6 (ответ не похож на HTML-документ).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIEF=""; OUT=""; TIMEOUT=630
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) [ "$#" -ge 2 ] || { echo "frontend.sh: у -o нет аргумента" >&2; exit 5; }
        OUT="$2"; shift 2 ;;
    -t) [ "$#" -ge 2 ] || { echo "frontend.sh: у -t нет аргумента" >&2; exit 5; }
        TIMEOUT="$2"; shift 2 ;;
    *)  BRIEF="$1"; shift ;;
  esac
done
[ -n "$BRIEF" ] && [ -r "$BRIEF" ] || { echo "frontend.sh: BRIEF_FILE обязателен и должен читаться" >&2; exit 5; }
[ -n "$OUT" ] || { echo "frontend.sh: -o OUT_HTML обязателен" >&2; exit 5; }

CONTEXT=$(cat "$BRIEF")
PROMPT="Ты — сильный фронтенд-дизайнер и верстальщик. Ниже бриф. Сделай максимально красиво и профессионально: продуманная композиция, выразительная типографика, деталировка и микро-анимации — строго в рамках ограничений брифа. Тексты пиши сам по брифу, по-русски, без клише.

$CONTEXT

Верни ТОЛЬКО полный самодостаточный HTML-документ (весь CSS/JS инлайн, внешние только Google Fonts), начиная строго с <!DOCTYPE html> и заканчивая </html>. Без markdown-ограждений и текста до/после."

TMP=$(mktemp /tmp/gemini-frontend-XXXXXX.html)
trap 'rm -f "$TMP"' EXIT
printf '%s' "$PROMPT" | "$DIR/agy-run.sh" -m pro -t "$TIMEOUT" -o "$TMP" || exit $?

# Валидация формы: начинается с doctype, кончается </html>; одиночное ограждение срезаем
if head -1 "$TMP" | grep -q '^```'; then sed -i '1d;$d' "$TMP"; fi
head -1 "$TMP" | grep -qi '^<!DOCTYPE html>' || { echo "frontend.sh: ответ не начинается с <!DOCTYPE html>" >&2; exit 6; }
tail -1 "$TMP" | grep -qi '</html>' || { echo "frontend.sh: ответ не заканчивается </html> (обрезан?)" >&2; exit 6; }

cp "$TMP" "$OUT"
echo "frontend.sh: HTML записан в $OUT ($(wc -c <"$OUT") байт)" >&2
