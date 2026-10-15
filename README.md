# Подключение MCP-сервера «Озвучка и липсинк»

Эндпоинт: **`https://lipsync.kachanov.io/mcp`**
Транспорт: **Streamable HTTP** (JSON-RPC 2.0), авторизация — **`Authorization: Bearer vl_…`**
Токен персональный: всё, что сделает агент, попадает в ваши задачи и голоса.

Проверено снаружи: `POST /mcp` без токена отдаёт `401 {"error":"unauthorized","detail":"Send a personal token: Authorization: Bearer vl_…"}`,
`GET /.well-known/oauth-authorization-server` → 404, т.е. OAuth-flow нет — нужен именно личный токен.

## Шаг 1. Получить токен

1. Открыть <https://lipsync.kachanov.io/> и войти (регистрация — по коду приглашения).
2. Вкладка **«Агенты»** → поле «Название токена» → **«Создать токен»**.
3. **Скопировать токен сразу** — второй раз он не показывается. Токенов можно завести несколько (по одному на компьютер/агента), лишние отзываются в таблице ниже.

## Шаг 2. Прописать в клиенте

Готовые сниппеты под все клиенты (подставьте токен):

```bash
./connect-lipsync-mcp.sh print vl_XXXX
```

Или сразу записать конфиг (существующий файл сливается, не затирается; делается бэкап):

```bash
./connect-lipsync-mcp.sh cline          vl_XXXX   # cline_mcp_settings.json
./connect-lipsync-mcp.sh cursor         vl_XXXX   # ~/.cursor/mcp.json
./connect-lipsync-mcp.sh claude-desktop vl_XXXX   # claude_desktop_config.json
./connect-lipsync-mcp.sh codex          vl_XXXX   # ~/.codex/config.toml
./connect-lipsync-mcp.sh claude-code    vl_XXXX   # печатает команду claude mcp add
```

`LIPSYNC_TOKEN=vl_XXXX` работает вместо аргумента, `MCP_URL` и `SERVER_NAME` переопределяют URL и имя сервера.

### Cline (VS Code / JetBrains)

`cline_mcp_settings.json` — путь: macOS `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/`,
Linux `~/.config/Code/...`, Windows `%APPDATA%\Code\...`.

```json
{
  "mcpServers": {
    "voice-lipsync": {
      "type": "streamableHttp",
      "url": "https://lipsync.kachanov.io/mcp",
      "headers": { "Authorization": "Bearer vl_XXXX" },
      "disabled": false
    }
  }
}
```

### Claude Code

```bash
claude mcp add --transport http --scope user voice-lipsync https://lipsync.kachanov.io/mcp \
  --header "Authorization: Bearer vl_XXXX"
claude mcp list        # у voice-lipsync должно быть Connected; в сессии — /mcp
```

### Cursor

`~/.cursor/mcp.json` (или `.cursor/mcp.json` проекта):

```json
{ "mcpServers": { "voice-lipsync": { "url": "https://lipsync.kachanov.io/mcp",
  "headers": { "Authorization": "Bearer vl_XXXX" } } } }
```

Проверка: Settings → MCP — зелёная точка и список инструментов.

### Claude Desktop

Settings → Developer → Edit Config, в `claude_desktop_config.json` (нужен установленный Node.js — Desktop ходит через прослойку `mcp-remote`):

```json
{
  "mcpServers": {
    "voice-lipsync": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://lipsync.kachanov.io/mcp", "--header", "Authorization:${AUTH}"],
      "env": { "AUTH": "Bearer vl_XXXX" }
    }
  }
}
```

### Codex

`~/.codex/config.toml` + переменная окружения (в `~/.zshrc`):

```toml
[mcp_servers.voice-lipsync]
url = "https://lipsync.kachanov.io/mcp"
bearer_token_env_var = "LIPSYNC_TOKEN"
```

```bash
export LIPSYNC_TOKEN="vl_XXXX"
```

Проверка: `codex mcp list`, в сессии — `/mcp`.

## Шаг 3. Проверить соединение

```bash
./check-lipsync-mcp.py vl_XXXX
```

Скрипт делает `initialize` + `tools/list` напрямую в эндпоинт и печатает имя сервера, версию протокола и список инструментов — не зависит от клиента.

```
→ https://lipsync.kachanov.io/mcp
✓ подключено: <сервер> v<версия>
  протокол: 2025-06-18
  инструментов: N
    • <tool> — <описание>
```

Затем — обычными словами агенту: «покажи мои голоса в voice-lipsync», «озвучь текст голосом «Хосе» и дай ссылку на mp3», «сделай говорящее видео 480p: фото …, текст …».

## Что умеет сервер (по `openapi.json` сервиса)

Задачи (озвучка/липсинк), голоса и клонирование голоса, диалекты, цитаты/предпросчёт цены, файлы результатов, статистика трат. REST-API сервиса по тому же адресу (`/openapi.json`) авторизуется тем же токеном — MCP по сути обёртка над ним.

## Полезно знать

- Фото и аудио агент передаёт ссылкой или файлом (base64), **до 50 МБ**.
- Видео 480p — $0.25, 720p — $0.50; ~10 минут на минуту речи. Если попросить «быстрее», длинная речь режется на части по $0.25 и ролик готовится ~15 минут при любой длине; цену агент узнаёт заранее через quote-инструмент и ждёт сам.
- Озвучка — секунды, но первая после паузы ждёт свободный GPU ~минуту.
- Ссылки на готовые файлы живут **7 дней** и отдаются без входа — можно переслать кому угодно.
- Смотрите поле «Распознано» (transcript): видно, что услышало распознавание речи.

## Свой API-ключ OpenRouter (для самого агента)

Токен `vl_…` из Шага 1 открывает доступ к MCP-серверу, но не оплачивает работу модели-агента — это разные вещи. Чтобы Cline думал вашей моделью за ваш счёт, ему нужен отдельный ключ провайдера, например OpenRouter.

1. Создайте ключ на <https://openrouter.ai/settings/keys> (формат `sk-or-v1-…`) и при необходимости пополните баланс на <https://openrouter.ai/credits>.
2. Cline (VS Code / JetBrains): значок настроек → **API Configuration** → **API Provider: OpenRouter** → вставьте ключ в поле **OpenRouter API Key** → выберите модель (актуальный список — на <https://openrouter.ai/models>).
3. Ключ сохраняется в защищённом хранилище VS Code и в конфиг-файлы (в т.ч. `cline_mcp_settings.json`) не попадает. В CLI/SDK тот же ключ передаётся как `providerId: "openrouter"` + `apiKey` + `modelId`, базовый URL — `https://openrouter.ai/api/v1`.

Проверка: на странице ключа в разделе **Usage** видны запросы, а сам Cline отвечает в чате — значит ключ принят.

## Диагностика

| Симптом | Причина / что делать |
|---|---|
| `401 unauthorized` | токен не передан, просрочен или отозван — заведите новый во вкладке «Агенты» |
| `403 Error 1010` от Cloudflare | экзотический User-Agent заблокирован; в `check-lipsync-mcp.py` он задаётся через `LIPSYNC_UA` |
| Claude Desktop: сервер не появился | нет Node.js/npx, либо Desktop не перезапущен |
| Cline: сервер красный | токен с лишними кавычками/пробелом, либо нет доступа в интернет |
| Инструменты не вызываются | включите тумблер сервера в списке MCP и подтвердите использование инструмента |
