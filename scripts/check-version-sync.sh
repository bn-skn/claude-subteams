#!/usr/bin/env bash
# check-version-sync.sh — версия в marketplace.json обязана совпадать с plugin.json.
#
# Зачем: 06.08.2026 обнаружен дрейф в пять минорных версий (marketplace 1.39.0
# против plugin 1.44.0). Маркетплейс-манифест — то, что читается при резолве,
# поэтому расхождение означает, что заказчик ставит не ту версию, которую мы
# считаем отгруженной, и диагностика начинается с ложной посылки.
#
# Режимы:
#   (без аргументов)  сверяет файлы рабочего дерева
#   --staged          сверяет содержимое ИНДЕКСА (используется git-хуком .githooks/pre-commit,
#                     иначе починенное рабочее дерево замаскировало бы битый коммит)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-worktree}"

read_json() { # $1 = путь относительно корня репо
  case "$MODE" in
    --staged) git -C "$DIR" show ":$1" ;;
    *)        cat "$DIR/$1" ;;
  esac
}

mp="$(read_json .claude-plugin/marketplace.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(next(p['version'] for p in d['plugins'] if p['name']=='claude-subteams'))")"
pj="$(read_json .claude-plugin/plugin.json | python3 -c "
import json,sys
print(json.load(sys.stdin)['version'])")"

if [ "$mp" != "$pj" ]; then
  echo "ОТКАЗ: marketplace.json=$mp, plugin.json=$pj — версии разошлись." >&2
  echo "Синхронизируй перед релизом: маркетплейс читается при резолве." >&2
  exit 1
fi
echo "версии синхронны: $pj"
