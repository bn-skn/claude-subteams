# Сводка прогона: jq -r -s -f summarize.jq stream.jsonl
# Ввод — весь stream-json (slurp). Делает run-scenario.sh; можно перезапустить
# вручную на сохранённом stream.jsonl.
def txt: if type == "string" then . elif type == "array" then (map(select(.type == "text") | .text) | join("\n")) else tostring end;
def clip($n): if length > $n then .[0:$n] + "…" else . end;
def oneline: gsub("\\s+"; " ");

. as $ev
| ($ev | map(select(.type == "system" and .subtype == "init")) | first // {}) as $init
| ($ev | map(select(.type == "result")) | last // {}) as $res
| [ $ev | to_entries[] | .key as $i | .value as $e
    | select($e.type == "assistant") | $e.message.content[]? | select(.type == "tool_use")
    | {i: $i, id: .id, name: .name, input: .input, nested: ($e.parent_tool_use_id != null)} ] as $uses
| [ $ev | to_entries[] | .key as $i | .value as $e
    | select($e.type == "user") | $e.message.content[]? | select(.type == "tool_result")
    | {i: $i, tid: .tool_use_id, err: (.is_error // false), text: (.content | txt)} ] as $results
| ($uses | map(select(.name == "Bash") | select((.input.command // "") | test("\\bgit\\b[^;&|]*\\bcommit\\b")))) as $commits
| ($commits | map(. as $u | ($results | map(select(.tid == $u.id)) | first) as $r
    | ($r != null and ($r.text | test("subteams:[a-z-]*gate|pre-commit-gate|Bypass is the user"; "i"))) as $d
    | $u + {res: $r, denied: $d,
            kind: (if ($d | not) then null
                   elif ($r.text | test("not covered by the required checks")) then "test-gate:missing-checks"
                   elif ($r.text | test("Test gate")) then "test-gate:other"
                   elif ($r.text | test("code-reviewer subagent")) then "review-gate"
                   else "gate:other" end)})) as $cm
# «сама / после отказа» считаем от первого отказа гейта ТЕСТОВ со списком недостающего: отказ гейта ревью
# или отказ формы коммита («git add && commit») ничего не говорит модели про тесты и агентов.
| ($cm | map(select(.kind == "test-gate:missing-checks")) | first | .i // null) as $firstDeny
| ($uses | map(select(.name == "Agent" or .name == "Task"))) as $spawns
| ($ev | map(select(.type == "system" and .subtype == "hook_response" and .hook_event != "SessionStart")
    | select(.outcome != "success" or ((.stdout // "") != "") or ((.stderr // "") != "")))) as $hooks
| ($res.result // "") as $final

| "=== RUN ===",
  "session:  \($res.session_id // $init.session_id // "?")",
  "model:    \($init.model // "?")   permissionMode: \($init.permissionMode // "?")",
  "cwd:      \($init.cwd // "?")",
  "turns:    \($res.num_turns // "?")   duration: \((($res.duration_ms // 0) / 1000 | floor))s   cost: $\($res.total_cost_usd // "?")",
  "result:   subtype=\($res.subtype // "NO RESULT EVENT")  is_error=\(if $res.is_error == null then "?" else ($res.is_error | tostring) end)  terminal=\($res.terminal_reason // "?")",
  "",
  "=== PLUGINS (init) ===",
  ($init.plugins // [] | map(select(.source | test("builtin") | not)) | map("  \(.name)  \(.source)  v\(.version // "?")  \(.path)") | if length == 0 then ["  (нет)"] else . end | .[]),
  (($init.plugins // []) as $p
    | ($p | map(select(.name | test("claude-subteams"))) ) as $s
    | if ($s | length) == 1 and ($s[0].source | test("inline")) then "  OK: загружена одна копия плагина (--plugin-dir), установленная не грузится"
      else "  ВНИМАНИЕ: claude-subteams загружено \($s | length) раз(а) / не inline — прогон невалиден" end),
  "",
  "=== SUBAGENTS (порядок запуска) ===",
  (if ($spawns | length) == 0 then "  (ни одного)" else
    ($spawns | to_entries[] | .key as $n | .value as $u
      | "  #\($n + 1) \($u.input.subagent_type // "(general-purpose)")  [\(if $u.nested then "nested" else "main" end)]  "
        + (if $firstDeny == null then "отказа гейта тестов (missing-checks) не было"
           elif $u.i > $firstDeny then "ПОСЛЕ первого отказа гейта тестов"
           else "ДО отказа гейта тестов (сама)" end)
        + "  — \(($u.input.description // "") | oneline | clip(80))") end),
  "",
  "=== subteams-tests / subteams-browser / agent-browser (Bash, порядок) ===",
  ($uses | map(select(.name == "Bash") | select((.input.command // "") | test("subteams-tests|subteams-browser|agent-browser")))
    | if length == 0 then ["  (ни одного вызова)"] else map("  [\(if .nested then "nested" else "main" end)] \((.input.command // "") | oneline | clip(170))") end | .[]),
  "",
  "=== GIT COMMIT (попытки) ===",
  (if ($cm | length) == 0 then "  (попыток коммита не было)" else
    ($cm | to_entries[] | .key as $n | .value as $c
      | "  #\($n + 1) [\(if $c.nested then "nested" else "main" end)] \((($c.input.command // "") | oneline | clip(200)))",
        "     -> \(if $c.res == null then "НЕТ РЕЗУЛЬТАТА" elif $c.denied then "ОТКАЗ ГЕЙТА [\($c.kind)]" elif $c.res.err then "ОШИБКА" else "ok" end): \(($c.res.text // "") | oneline | clip(900))") end),
  "",
  "=== permission_denials (CLI; отказы хуков тоже попадают сюда) ===",
  (($res.permission_denials // []) | if length == 0 then ["  (нет)"] else map("  \(.tool_name): \((.tool_input | tostring | oneline | clip(160)))") end | .[]),
  "",
  "=== hook_response вне SessionStart: только отказы и непустой вывод (предупреждения гейта, systemMessage) ===",
  (if ($hooks | length) == 0 then "  (нет событий)" else ($hooks | map("  \(.hook_name) outcome=\(.outcome // "?") exit=\(.exit_code // "?") stdout=\((.stdout // "") | oneline | clip(500)) stderr=\((.stderr // "") | oneline | clip(500))")[]) end),
  "",
  "=== ФЛАГИ ИТОГОВОГО ОТВЕТА ===",
  "  упоминает скриншоты:        \(if $final | test("скриншот|screenshot|\\.png"; "i") then "да" else "нет" end)",
  "  упоминает доработки:        \(if $final | test("доработ|улучшен|улучшить|рекоменд|improvement"; "i") then "да" else "нет" end)",
  "  упоминает пропуск/degraded: \(if $final | test("пропущ|не выполнен|degraded|недоступн|не смог|не запуска"; "i") then "да" else "нет" end)",
  "  упоминает предупреждение:   \(if $final | test("предупрежд|warning"; "i") then "да" else "нет" end)",
  "",
  "=== ИТОГОВЫЙ ОТВЕТ ===",
  $final
