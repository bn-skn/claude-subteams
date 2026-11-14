#!/bin/bash
# Один прогон приёмки 1.50 (docs/plans/active/2026-11-13-testing-ui-1.50.0.md, Задача 8).
#
#   run-scenario.sh <E1..E12|SMOKE> <workdir>   — подготовить фикстуру и запустить ОДНУ headless-сессию
#   run-scenario.sh --list                      — id и промпты
#   run-scenario.sh --check-docs                — все промпты дословно есть в scenarios.md
#
# <workdir> — абсолютный путь, не существует или пуст. Исключения (scenarios.md):
#   E7 — рабочий каталог завершённого прогона E1; E8 — готовый worktree claudebot
#   (фикстура не создаётся); E9 — пустой каталог (фикстура не создаётся).
# Результат: tests/ui-pipeline/runs/<id>-<timestamp>/{stream.jsonl,stderr.log,summary.txt,meta.txt}
#
# Чистота прогона:
#   - окружение пустое (env -i): HOME, PATH, TERM, LANG; токен OAuth подгружается
#     ВНУТРИ процесса из ~/.claude-code-token.env и не попадает ни в argv, ни в логи
#     (в логах sk-ant-… дополнительно вычищается);
#   - --setting-sources project,local: пользовательские настройки, плагины и скиллы не читаются,
#     поэтому установленные плагины (в т.ч. claude-subteams@articortex 1.49.0), их
#     хуки и MCP не загружаются; грузится только копия из репозитория (--plugin-dir);
#   - --strict-mcp-config: MCP-серверы пользователя не поднимаются;
#   - права: явный allowlist, без bypass-режимов; git push, sudo и `claude plugin` запрещены.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
MODEL="${SCENARIO_MODEL:-claude-opus-5-5}"
TIMEOUT_S="${SCENARIO_TIMEOUT_S:-1500}"
TOKEN_FILE="${CLAUDE_TOKEN_FILE:-$HOME/.claude-code-token.env}"
NODE_BIN="$(dirname "$(command -v node)")"
PORT=4517

# ------------------------------------------------------------- промпты
# Обычные просьбы: без слов «тест», «проверь», «ui-tester»; всегда с «закоммить».
prompt_for() {
  case "$1" in
    SMOKE) echo "${SMOKE_PROMPT:-Скажи привет одним словом.}" ;;
    E1)  echo "Переделай форму заявки: добавь поле телефона и поменяй подпись кнопки на «Получить консультацию». И закоммить." ;;
    E2)  echo "Переверстай шапку: сделай заголовок крупнее, добавь под ним подзаголовок, а кнопку «Связаться» поставь справа. И закоммить." ;;
    E3)  prompt_for E1 ;;
    E4)  echo "Поправь опечатку в README и закоммить." ;;
    E5)  echo "Поменяй формат ответа API формы: вместо полей ok и message пусть отдаёт status со значением accepted и text с благодарностью. И закоммить." ;;
    E6)  echo "Поправь письмо emails/welcome.html: поменяй приветствие на «Добрый день!» и добавь внизу подпись менеджера. И закоммить." ;;
    E7)  echo "Добавь в форму выпадающий список «Тема обращения» с тремя вариантами и поле для комментария. И закоммить." ;;
    E8)  echo "В веб-чате сделай подпись-подсказку под полем ввода крупнее: 13px вместо 12px, во всех четырёх видах. И закоммить." ;;
    E9)  echo "Сделай маленькое веб-приложение со списком дел через сабтимс и закоммить." ;;
    E10) echo "В валидации заявки запрети имена, состоящие только из цифр. И закоммить." ;;
    E11) echo "Добавь ограничение частоты для API формы: не больше 5 заявок в минуту с одного IP, остальные получают ответ 429 с понятным сообщением, и это сообщение должно показываться в форме. И закоммить." ;;
    E12) echo "Оформи форму как карточку: белый фон, тонкая рамка, скруглённые углы, мягкая тень, увеличь отступы между полями, а кнопку сделай тёмно-зелёной. И закоммить." ;;
    *) return 1 ;;
  esac
}
ALL_IDS="SMOKE E1 E2 E3 E4 E5 E6 E7 E8 E9 E10 E11 E12"

die() { echo "run-scenario: $*" >&2; exit 2; }

case "${1:-}" in
  --list) for id in $ALL_IDS; do printf '%s\t%s\n' "$id" "$(prompt_for "$id")"; done; exit 0 ;;
  --check-docs)
    rc=0
    for id in $ALL_IDS; do
      [ "$id" = SMOKE ] && continue
      [ "$id" = E3 ] && continue # = E1, в документе ссылкой
      grep -qF -- "$(prompt_for "$id")" "$HERE/scenarios.md" || { echo "нет в scenarios.md: $id" >&2; rc=1; }
    done
    [ $rc = 0 ] && echo "scenarios.md: промпты совпадают"
    exit $rc ;;
  -h|--help|"") sed -n '2,24p' "$0"; exit 0 ;;
esac

ID="$1"; WORKDIR="${2:-}"
PROMPT="$(prompt_for "$ID")" || die "неизвестный сценарий $ID (см. --list)"
[ -n "$WORKDIR" ] || die "usage: run-scenario.sh <id> <workdir>"
case "$WORKDIR" in /*) ;; *) die "workdir должен быть абсолютным путём" ;; esac

command -v jq >/dev/null || die "нужен jq"
command -v claude >/dev/null || die "claude не найден в PATH"
[ -r "$TOKEN_FILE" ] || die "нет файла токена $TOKEN_FILE"
[ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ] || die "не похоже на каталог плагина: $PLUGIN_DIR"

# Порт приложения должен быть свободен: webServer конфига переиспользует чужой сервер.
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$PORT\$"; then
  die "порт $PORT занят — остановите процесс (reuseExistingServer подхватил бы чужой сервер)"
fi

# ------------------------------------------------------------- фикстура
case "$ID" in
  E7)
    [ -d "$WORKDIR/.git" ] || die "E7 идёт ПОСЛЕ E1: передайте рабочий каталог завершённого прогона E1"
    [ "$(git -C "$WORKDIR" rev-list --count HEAD)" -ge 3 ] || die "в $WORKDIR нет коммита от E1 (ожидается ≥3 коммитов)"
    [ -z "$(git -C "$WORKDIR" status --porcelain)" ] || die "в $WORKDIR есть незакоммиченные изменения — E1 не завершён"
    ;;
  E8)
    # Готовый worktree claudebot (git worktree add …), контракт уже в HEAD ветки. Прод не трогаем.
    [ -e "$WORKDIR/.git" ] || die "E8: $WORKDIR не git-worktree"
    [ -z "$(git -C "$WORKDIR" status --porcelain)" ] || die "E8: в worktree есть незакоммиченные изменения"
    # без -q: grep -q закрывает пайп на первом совпадении, git show получает SIGPIPE, pipefail даёт 141
    git -C "$WORKDIR" show HEAD:CLAUDE.md 2>/dev/null | grep '^<!-- subteams:test-suites v1 -->' >/dev/null \
      || die "E8: в HEAD worktree нет контракта (сначала коммит контракта в claudebot)"
    ;;
  E9)
    [ -z "$(ls -A "$WORKDIR" 2>/dev/null)" ] || die "E9: каталог должен быть пустым"
    mkdir -p "$WORKDIR"
    ;;
  E12) bash "$HERE/make-fixture.sh" --no-contract --no-verify "$WORKDIR" >&2 ;;
  *)   bash "$HERE/make-fixture.sh" --no-verify "$WORKDIR" >&2 ;;
esac
WORKDIR="$(cd "$WORKDIR" && pwd)"

# ------------------------------------------------------------- окружение
TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$HERE/runs/$ID-$TS"
mkdir -p "$RUN_DIR"

ENV_EXTRA=()                     # дополнительные VAR=value для env -i
SESSION_PATH="$NODE_BIN:/usr/local/bin:/usr/bin:/bin"
SETUP_NOTE="стандартное окружение"
if [ "$ID" = E3 ]; then
  # agent-browser недоступен: нет в PATH (лежит рядом с node → в PATH только
  # node/npm/npx/claude через shim), кэш плагина пуст (изолированный XDG_CACHE_HOME),
  # автоустановка выключена.
  SHIM="$RUN_DIR/shim"; mkdir -p "$SHIM" "$RUN_DIR/xdg-cache"
  for b in node npm npx claude; do
    src="$(command -v "$b" || true)"
    [ -n "$src" ] && ln -s "$src" "$SHIM/$b"
  done
  SESSION_PATH="$SHIM:/usr/local/bin:/usr/bin:/bin"
  ENV_EXTRA+=("CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1" "XDG_CACHE_HOME=$RUN_DIR/xdg-cache")
  if PATH="$SESSION_PATH" command -v agent-browser >/dev/null 2>&1; then
    die "E3: agent-browser всё ещё виден в PATH ($(PATH="$SESSION_PATH" command -v agent-browser))"
  fi
  SETUP_NOTE="E3: agent-browser скрыт из PATH, XDG_CACHE_HOME пуст, CLAUDE_SUBTEAMS_NO_AUTO_INSTALL=1"
fi

{
  echo "scenario:  $ID"
  echo "workdir:   $WORKDIR"
  echo "plugin:    $PLUGIN_DIR (version $(jq -r .version "$PLUGIN_DIR/.claude-plugin/plugin.json"))"
  echo "model:     $MODEL"
  echo "timeout:   ${TIMEOUT_S}s"
  echo "setup:     $SETUP_NOTE"
  echo "started:   $(date -Is)"
  echo "prompt:    $PROMPT"
  echo "fixture HEAD: $(git -C "$WORKDIR" log --oneline -1 2>/dev/null || echo '(нет git)')"
} > "$RUN_DIR/meta.txt"

echo "run-scenario: $ID -> $RUN_DIR" >&2

# ------------------------------------------------------------- запуск
# Токен читается ВНУТРИ чистого процесса (bash -c), поэтому его нет ни в argv, ни в окружении родителя.
ALLOWED=(Bash Read Edit Write Glob Grep Agent Task Skill TodoWrite)
DENIED=('Bash(git push:*)' 'Bash(sudo:*)' 'Bash(claude plugin:*)' 'Bash(claude mcp:*)' 'Bash(*self-restart*)' 'Bash(*systemctl*)')
START=$(date +%s)
set +e
(
  cd "$WORKDIR"
  timeout --kill-after=20 "$TIMEOUT_S" \
    env -i HOME="$HOME" PATH="$SESSION_PATH" TERM=dumb LANG=C.UTF-8 ${ENV_EXTRA[@]+"${ENV_EXTRA[@]}"} \
    bash -c 'set -a; . "$1"; set +a; shift; exec claude "$@"' _ "$TOKEN_FILE" \
      -p "$PROMPT" \
      --plugin-dir "$PLUGIN_DIR" \
      --model "$MODEL" \
      --output-format stream-json --verbose --include-hook-events \
      --setting-sources project,local --strict-mcp-config \
      --permission-mode default \
      --allowedTools "${ALLOWED[@]}" \
      --disallowedTools "${DENIED[@]}"
) > "$RUN_DIR/stream.jsonl" 2> "$RUN_DIR/stderr.log"
RC=$?
set -e
END=$(date +%s)

# Страховка от утечки токена в логи (модель могла сделать `env`).
sed -i -E 's/sk-ant-[A-Za-z0-9_-]+/sk-ant-[REDACTED]/g' "$RUN_DIR/stream.jsonl" "$RUN_DIR/stderr.log"

# Уборка: сервер приложения, оставшийся в этом workdir.
for pid in $(pgrep -f 'node server.js' 2>/dev/null || true); do
  if [ "$(readlink "/proc/$pid/cwd" 2>/dev/null || true)" = "$WORKDIR" ]; then kill "$pid" 2>/dev/null || true; fi
done

{
  echo "finished:  $(date -Is)   exit=$RC$([ "$RC" = 124 ] && echo ' (TIMEOUT)')   wall=$((END - START))s"
} >> "$RUN_DIR/meta.txt"

{
  cat "$RUN_DIR/meta.txt"
  echo
  jq -r -s -f "$HERE/summarize.jq" "$RUN_DIR/stream.jsonl" 2>&1 || echo "(summarize.jq упал — смотрите stream.jsonl)"
  echo
  echo "=== GIT в workdir (итоговое состояние) ==="
  { git -C "$WORKDIR" log --oneline | head -8; } 2>&1 || true
  echo "--- status:"
  { git -C "$WORKDIR" status --short | head -20; } 2>&1 || true
  echo "--- последний коммит:"
  { git -C "$WORKDIR" show --stat --format='%h %s' HEAD 2>&1 | head -15; } || true
} > "$RUN_DIR/summary.txt"

echo "run-scenario: готово, exit=$RC, wall=$((END - START))s; сводка: $RUN_DIR/summary.txt" >&2
exit "$RC"
