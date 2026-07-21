#!/usr/bin/env bash
# design-critic.sh — прямой вызов Gemini-критики отрендеренных визуалов без LLM-прослойки.
# Использование: design-critic.sh -c CONTEXT_FILE [-o OUTFILE] IMG1 [IMG2 ...]
#   CONTEXT_FILE  текстовый файл: что за артефакт, аудитория, бренд-ограничения (свободный текст, кавычки безопасны)
#   IMG*          АБСОЛЮТНЫЕ пути к скриншотам/рендерам
# Выходные коды как у agy-run.sh + 5 (нет входов).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX_FILE=""; OUTFLAG=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c) [ "$#" -ge 2 ] || { echo "design-critic.sh: у -c нет аргумента" >&2; exit 5; }
        CTX_FILE="$2"; shift 2 ;;
    -o) [ "$#" -ge 2 ] || { echo "design-critic.sh: у -o нет аргумента" >&2; exit 5; }
        OUTFLAG=(-o "$2"); shift 2 ;;
    --) shift; break ;;
    *)  break ;;
  esac
done
[ "$#" -ge 1 ] || { echo "design-critic.sh: не переданы изображения" >&2; exit 5; }
[ -n "$CTX_FILE" ] && [ -r "$CTX_FILE" ] || { echo "design-critic.sh: -c CONTEXT_FILE обязателен и должен читаться" >&2; exit 5; }

IMAGE_PATHS=""
MISSING=0
for p in "$@"; do
  case "$p" in /*) : ;; *) echo "design-critic.sh: путь не абсолютный: $p" >&2; exit 5 ;; esac
  if [ -e "$p" ]; then IMAGE_PATHS="${IMAGE_PATHS}${p}"$'\n'; else echo "design-critic.sh: missing: $p" >&2; MISSING=1; fi
done
[ -n "$IMAGE_PATHS" ] || { echo "design-critic.sh: все входы отсутствуют" >&2; exit 5; }
[ "$MISSING" -eq 1 ] && echo "design-critic.sh: часть входов пропущена, ревью только по существующим" >&2

CONTEXT=$(cat "$CTX_FILE")

PROMPT="You are a senior product designer giving an independent visual critique. Use ONLY your read_file tool (terminal commands are forbidden) to open each of these rendered images:
$IMAGE_PATHS
Context: $CONTEXT

Evaluate what you SEE: visual hierarchy, typography, spacing/alignment, color and contrast (flag anything below WCAG AA), imagery quality, overflow/clipping artifacts, responsive integrity across provided breakpoints, and overall taste — intentional and current, or template-generic. Judge the pixels, not hypothetical code.

Return ONLY a valid JSON object — no markdown fences, no prose:
{\"findings\":[{\"severity\":\"critical|high|medium|low\",\"target\":\"...\",\"aspect\":\"hierarchy|typography|spacing|color|imagery|artifact|responsive|taste\",\"issue\":\"...\",\"fix\":\"...\"}],\"what_works\":[\"...\"],\"summary\":\"...\"}"

printf '%s' "$PROMPT" | "$DIR/agy-run.sh" -m pro -j -t 330 "${OUTFLAG[@]}"
