#!/bin/bash
# Фикстура приёмки 1.50 (docs/plans/active/2026-11-13-testing-ui-1.50.0.md, Задача 8).
# Собирает свежий git-репозиторий с маленьким веб-приложением:
#   Node без зависимостей (node:http), форма заявки, POST /api/lead,
#   шапка «на грани переполнения» на 320px, Playwright Test с webServer,
#   юнит-тест (node --test) и контракт тестов v1 в CLAUDE.md.
#
# Использование:
#   make-fixture.sh [--no-contract] [--no-verify] <dest-dir>
#     --no-contract  тот же проект, CLAUDE.md без блока контракта (сценарий E12)
#     --no-verify    не гонять контрольный прогон хрупкости шапки
#
# <dest-dir> должен не существовать или быть пустым. Коммиты делает сам скрипт
# обычным git (хуки плагина тут не работают):
#   1. «initial»  — всё приложение, CLAUDE.md без блока контракта
#      (в README.md намеренная опечатка «принемает» — для сценария E4);
#   2. «contract» — ТОЛЬКО CLAUDE.md с блоком (правка контракта — отдельным
#      коммитом, R11; контракт обязан лежать в HEAD).
#
# Браузер e2e — системный Chrome (channel: 'chrome'): Chromium из кэша
# Playwright на этой машине требует --no-sandbox, а мы этого не включаем.
# Версия @playwright/test запинена на 1.61.1 (лежит в кэше npm).
set -euo pipefail

CONTRACT=1
VERIFY=1
DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-contract) CONTRACT=0 ;;
    --no-verify) VERIFY=0 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "make-fixture: неизвестный флаг $1" >&2; exit 2 ;;
    *) [ -z "$DEST" ] || { echo "make-fixture: лишний аргумент $1" >&2; exit 2; }; DEST="$1" ;;
  esac
  shift
done
[ -n "$DEST" ] || { echo "usage: make-fixture.sh [--no-contract] [--no-verify] <dest-dir>" >&2; exit 2; }

if [ -e "$DEST" ] && { [ ! -d "$DEST" ] || [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; }; then
  echo "make-fixture: $DEST существует и не пуст — отказ" >&2
  exit 1
fi
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
cd "$DEST"

mkdir -p public lib tests/unit e2e emails

# ---------------------------------------------------------------- приложение
cat > package.json <<'EOF'
{
  "name": "lead-form-demo",
  "version": "1.0.0",
  "private": true,
  "description": "Лендинг с формой заявки (фикстура приёмки claude-subteams)",
  "scripts": {
    "start": "node server.js",
    "test": "node --test tests/unit/*.test.js",
    "test:e2e": "playwright test"
  },
  "devDependencies": {
    "@playwright/test": "1.61.1"
  }
}
EOF

cat > .gitignore <<'EOF'
node_modules/
test-results/
playwright-report/
blob-report/
EOF

cat > lib/lead.js <<'EOF'
'use strict'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// Проверка заявки. Чистая функция: нет ввода-вывода, легко тестировать.
function validateLead(input) {
  const errors = []
  const name = typeof input?.name === 'string' ? input.name.trim() : ''
  const email = typeof input?.email === 'string' ? input.email.trim() : ''
  if (name.length < 2) errors.push('name')
  if (name.length > 100) errors.push('name')
  if (!EMAIL_RE.test(email) || email.length > 200) errors.push('email')
  return { ok: errors.length === 0, errors: [...new Set(errors)], lead: { name, email } }
}

module.exports = { validateLead }
EOF

cat > server.js <<'EOF'
'use strict'
const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')
const { validateLead } = require('./lib/lead')

const PORT = Number(process.env.PORT) || 4517
const PUBLIC = path.join(__dirname, 'public')
const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8' }

function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(body))
}

function handleLead(req, res) {
  let raw = ''
  req.on('data', (chunk) => {
    raw += chunk
    if (raw.length > 10_000) req.destroy()
  })
  req.on('end', () => {
    let input
    try { input = JSON.parse(raw) } catch { return sendJson(res, 400, { ok: false, errors: ['json'] }) }
    const result = validateLead(input)
    if (!result.ok) return sendJson(res, 400, { ok: false, errors: result.errors })
    sendJson(res, 200, { ok: true, message: `Спасибо, ${result.lead.name}! Заявка принята.` })
  })
}

function serveStatic(req, res) {
  const url = new URL(req.url, 'http://localhost')
  const rel = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname).replace(/^\/+/, '')
  const file = path.resolve(PUBLIC, rel)
  if (file !== PUBLIC && !file.startsWith(PUBLIC + path.sep)) { res.writeHead(403); return res.end('Forbidden') }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Not found') }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' })
    res.end(data)
  })
}

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/api/lead') return handleLead(req, res)
  if (req.method === 'GET') return serveStatic(req, res)
  res.writeHead(405); res.end('Method not allowed')
})

server.listen(PORT, () => console.log(`lead-form-demo: http://localhost:${PORT}`))
process.on('SIGTERM', () => server.close(() => process.exit(0)))
process.on('SIGINT', () => server.close(() => process.exit(0)))
EOF

cat > public/index.html <<'EOF'
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Студия Лид</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <header class="site-header">
    <h1 class="brand">Студия Лид</h1>
    <a class="cta" href="#lead-form">Связаться</a>
  </header>
  <main>
    <p class="lead-text">Оставьте заявку, и мы свяжемся с вами в течение рабочего дня.</p>
    <form id="lead-form" novalidate>
      <label for="name">Имя</label>
      <input id="name" name="name" type="text" autocomplete="name" required>
      <label for="email">Email</label>
      <input id="email" name="email" type="email" autocomplete="email" required>
      <button type="submit">Отправить</button>
    </form>
    <p id="result" role="status" aria-live="polite"></p>
  </main>
  <script src="/app.js"></script>
</body>
</html>
EOF

cat > public/style.css <<'EOF'
* { box-sizing: border-box; }
body { margin: 0; font-family: system-ui, sans-serif; color: #1b1f2a; background: #f5f6fa; }
.site-header { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 16px; background: #16213e; color: #fff; }
.brand { margin: 0; font-size: 1.45rem; white-space: nowrap; }
.cta { white-space: nowrap; padding: 8px 12px; border: 1px solid #fff; border-radius: 6px; color: #fff; text-decoration: none; }
main { max-width: 480px; margin: 0 auto; padding: 24px 16px; }
form { display: grid; gap: 8px; }
input { padding: 10px; font-size: 1rem; border: 1px solid #b8bdd0; border-radius: 6px; }
button { margin-top: 8px; padding: 12px; font-size: 1rem; border: 0; border-radius: 6px; background: #0f62fe; color: #fff; cursor: pointer; }
#result { min-height: 1.5em; font-weight: 600; }
EOF

cat > public/app.js <<'EOF'
'use strict'
const form = document.getElementById('lead-form')
const result = document.getElementById('result')

form.addEventListener('submit', async (event) => {
  event.preventDefault()
  result.textContent = ''
  const payload = { name: form.elements.name.value, email: form.elements.email.value }
  try {
    const response = await fetch('/api/lead', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    const data = await response.json()
    // Сообщение об успехе приходит из ответа API.
    result.textContent = data.ok ? data.message : 'Проверьте поля формы.'
  } catch {
    result.textContent = 'Сеть недоступна, попробуйте позже.'
  }
})
EOF

cat > emails/welcome.html <<'EOF'
<!doctype html>
<html lang="ru">
<body style="font-family: Arial, sans-serif">
  <h1 style="font-size: 20px">Здравствуйте!</h1>
  <p>Мы получили вашу заявку и скоро свяжемся с вами.</p>
  <p>Студия Лид</p>
</body>
</html>
EOF

cat > README.md <<'EOF'
# lead-form-demo

Лендинг студии с формой заявки.

## Запуск

    npm install
    npm start

Сервер принемает заявки на `POST /api/lead` и отвечает JSON с полями `ok` и `message`.
EOF

# ------------------------------------------------------------------- тесты
cat > tests/unit/lead.test.js <<'EOF'
'use strict'
const test = require('node:test')
const assert = require('node:assert/strict')
const { validateLead } = require('../../lib/lead')

test('валидная заявка проходит и нормализуется', () => {
  const r = validateLead({ name: '  Иван ', email: 'ivan@example.com ' })
  assert.equal(r.ok, true)
  assert.deepEqual(r.lead, { name: 'Иван', email: 'ivan@example.com' })
})

test('короткое имя и плохой email отклоняются', () => {
  const r = validateLead({ name: 'И', email: 'не-почта' })
  assert.equal(r.ok, false)
  assert.deepEqual(r.errors.sort(), ['email', 'name'])
})

test('не объект и нестроковые поля не падают', () => {
  assert.equal(validateLead(null).ok, false)
  assert.equal(validateLead({ name: 42, email: [] }).ok, false)
})
EOF

cat > playwright.config.ts <<'EOF'
import { defineConfig, devices } from '@playwright/test'

// Порт фиксирован литералом: контракт (app.url) и baseURL должны совпадать.
// Браузер — системный Chrome: Chromium из кэша Playwright на этой машине
// требует --no-sandbox, а мы его не включаем.
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:4517',
    trace: 'off',
    video: 'off',
    screenshot: 'off',
  },
  projects: [{ name: 'chrome', use: { ...devices['Desktop Chrome'], channel: 'chrome' } }],
  webServer: {
    command: 'node server.js',
    url: 'http://localhost:4517',
    reuseExistingServer: true,
    timeout: 15_000,
    env: { PORT: '4517' },
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5_000 },
  },
})
EOF

cat > e2e/lead-form.spec.ts <<'EOF'
import { test, expect } from '@playwright/test'

test('заявка отправляется, успех приходит из ответа API', async ({ page }) => {
  await page.goto('/')
  await page.getByLabel('Имя').fill('Иван')
  await page.getByLabel('Email').fill('ivan@example.com')

  const [response] = await Promise.all([
    page.waitForResponse((r) => r.url().endsWith('/api/lead') && r.request().method() === 'POST'),
    page.getByRole('button', { name: 'Отправить' }).click(),
  ])

  // Контракт ответа API: ok + message.
  expect(response.status()).toBe(200)
  const body = await response.json()
  expect(body.ok).toBe(true)
  expect(typeof body.message).toBe('string')

  await expect(page.locator('#result')).toHaveText('Спасибо, Иван! Заявка принята.')
})
EOF

# --------------------------------------------------------------- CLAUDE.md
cat > CLAUDE.md <<'EOF'
# lead-form-demo

Маленький лендинг студии: шапка, форма заявки (имя, email), ответ сервера показывается под формой.
Сервер на `node:http` без зависимостей, статика в `public/`, API `POST /api/lead` (валидация в `lib/lead.js`).
Письма-шаблоны лежат в `emails/` и в приложение не входят.

## Команды

- `npm start` — сервер на `http://localhost:4517` (порт из `PORT`)
- `npm test` — юнит-тесты (`node --test`)
- `npm run test:e2e` — Playwright Test, системный Chrome, сервер поднимает сам конфиг (`webServer`)

## Правила

- Зависимостей у приложения нет и не добавляем; Playwright — только devDependency.
- Тексты на русском.
EOF

CONTRACT_BLOCK='<!-- subteams:test-suites v1 -->
```json
{
  "suites": [
    {"name": "unit", "cmd": "npm test", "kind": "unit", "run": "auto", "paths": ["server.js", "lib/**", "tests/unit/**"]},
    {"name": "e2e", "cmd": "npm run test:e2e", "kind": "e2e", "run": "auto"}
  ],
  "ui_globs": ["public/**", "**/*.html", "**/*.css"],
  "ui_exclude": ["emails/**"],
  "code_globs": ["server.js", "lib/**"],
  "test_globs": ["**/*.test.*", "**/*.spec.*", "tests/**", "e2e/**"],
  "app": {"url": "http://localhost:4517", "start": "playwright-webServer"},
  "small_change": {"max_lines": 10, "max_files": 2}
}
```
<!-- /subteams:test-suites -->'

# ------------------------------------------------------ установка и прогон
echo "== npm install" >&2
npm install --prefer-offline --no-audit --no-fund >&2
echo "== npm test" >&2
npm test >&2
echo "== npm run test:e2e" >&2
npm run test:e2e >&2

# ------------------------------------------- контрольный прогон хрупкости
if [ "$VERIFY" = 1 ]; then
  echo "== verify: шапка на 320px" >&2
  VERIFY_JS="$(mktemp -t fixture-verify.XXXXXX.cjs)"
  trap 'rm -f "$VERIFY_JS"' EXIT
  cat > "$VERIFY_JS" <<'EOF'
const { chromium } = require('@playwright/test')
const url = process.argv[2]
;(async () => {
  const browser = await chromium.launch({ channel: 'chrome' })
  const page = await browser.newPage({ viewport: { width: 320, height: 640 } })
  await page.goto(url)
  // запас = свободное место между заголовком и кнопкой сверх gap (12px); <0 — переполнение
  const slack = async () => page.evaluate(() => Math.round(document.querySelector('.cta').getBoundingClientRect().left - document.querySelector('.brand').getBoundingClientRect().right - 12))
  const overflows = async () => page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)
  const base = { overflow: await overflows(), slack: await slack() }
  await page.addStyleTag({ content: '.brand{font-size:1.9rem}' })
  const big = { overflow: await overflows(), slack: await slack() }
  await browser.close()
  console.log(JSON.stringify({ base, big }))
  if (base.overflow || base.slack < 0 || base.slack > 16) { console.error('база: должна влезать с запасом 0..16px'); process.exit(1) }
  if (!big.overflow) { console.error('крупный заголовок не вызвал переполнение'); process.exit(1) }
})().catch((e) => { console.error(e); process.exit(1) })
EOF
  VPORT=4598
  PORT=$VPORT node server.js >/dev/null 2>&1 &
  VPID=$!
  for _ in $(seq 1 40); do curl -sf "http://localhost:$VPORT/" >/dev/null 2>&1 && break; sleep 0.25; done
  VRC=0
  NODE_PATH="$DEST/node_modules" node "$VERIFY_JS" "http://localhost:$VPORT/" >&2 || VRC=$?
  kill "$VPID" 2>/dev/null || true
  wait "$VPID" 2>/dev/null || true
  [ "$VRC" = 0 ] || exit "$VRC"
fi

# ------------------------------------------------------------------ коммиты
git init -q -b main
git config user.name "Fixture Bot"
git config user.email "fixture@example.invalid"
git config commit.gpgsign false
git add -A
git commit -q -m "initial: lead form demo"
if [ "$CONTRACT" = 1 ]; then
  printf '\n## Контракт тестов\n\n%s\n' "$CONTRACT_BLOCK" >> CLAUDE.md
  git add CLAUDE.md
  git commit -q -m "chore: test contract v1"
fi
git status --short | grep . >&2 && { echo "make-fixture: после коммитов дерево грязное" >&2; exit 1; }
echo "fixture ready: $DEST ($(git log --oneline | wc -l) commits, contract=$CONTRACT)" >&2
