#!/usr/bin/env bash
# check-version-sync.sh — версия в marketplace.json обязана совпадать с plugin.json.
#
# Зачем: 02.08.2026 обнаружен дрейф в пять минорных версий (marketplace 1.39.0
# против plugin 1.44.0). Маркетплейс-манифест — то, что читается при резолве,
# поэтому расхождение означает, что заказчик ставит не ту версию, которую мы
# считаем отгруженной, и диагностика начинается с ложной посылки.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mp="$(python3 -c "import json;d=json.load(open('$DIR/.claude-plugin/marketplace.json'));print(next(p['version'] for p in d['plugins'] if p['name']=='claude-subteams'))")"
pj="$(python3 -c "import json;print(json.load(open('$DIR/.claude-plugin/plugin.json'))['version'])")"
if [ "$mp" != "$pj" ]; then
  echo "ОТКАЗ: marketplace.json=$mp, plugin.json=$pj — версии разошлись." >&2
  echo "Синхронизируй перед релизом: маркетплейс читается при резолве." >&2
  exit 1
fi
echo "версии синхронны: $pj"
