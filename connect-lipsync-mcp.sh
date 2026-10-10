#!/usr/bin/env bash
# Подключение MCP-сервера «Озвучка и липсинк» (lipsync.kachanov.io) к агенту.
#
#   ./connect-lipsync-mcp.sh print                  # готовые сниппеты для всех клиентов
#   ./connect-lipsync-mcp.sh cline   vl_XXXX        # → cline_mcp_settings.json
#   ./connect-lipsync-mcp.sh cursor  vl_XXXX        # → ~/.cursor/mcp.json
#   ./connect-lipsync-mcp.sh claude-desktop vl_XXXX # → claude_desktop_config.json
#   ./connect-lipsync-mcp.sh codex   vl_XXXX        # → ~/.codex/config.toml
#   ./connect-lipsync-mcp.sh claude-code vl_XXXX    # печатает команду `claude mcp add`
#
# Токен берётся из аргумента или из $LIPSYNC_TOKEN.
# URL переопределяется через $MCP_URL, имя сервера — через $SERVER_NAME.
#
# Токен создаётся на https://lipsync.kachanov.io/ → вкладка «Агенты» → «Создать токен».

set -euo pipefail

SERVER_NAME="${SERVER_NAME:-voice-lipsync}"
MCP_URL="${MCP_URL:-https://lipsync.kachanov.io/mcp}"

die() { printf '%s\n' "$*" >&2; exit 1; }

config_path() {
  case "$1" in
    cline)
      case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" ;;
        MINGW*|MSYS*|CYGWIN*) echo "${APPDATA:-$HOME/AppData/Roaming}/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" ;;
        *) echo "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" ;;
      esac ;;
    claude-desktop)
      case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
        MINGW*|MSYS*|CYGWIN*) echo "${APPDATA:-$HOME/AppData/Roaming}/Claude/claude_desktop_config.json" ;;
        *) echo "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
      esac ;;
    cursor) echo "$HOME/.cursor/mcp.json" ;;
    codex)  echo "$HOME/.codex/config.toml" ;;
    *) die "неизвестный клиент: $1" ;;
  esac
}

# JSON-клиенты: cline / cursor / claude-desktop. Существующий файл сливается, не затирается.
write_json() {
  local client="$1" path="$2" token="$3"
  command -v python3 >/dev/null || die "нужен python3"
  mkdir -p "$(dirname "$path")"
  [ -s "$path" ] || printf '{}\n' > "$path"
  cp "$path" "$path.bak.$(date +%s)" 2>/dev/null || true
  CLIENT="$client" SERVER_NAME="$SERVER_NAME" MCP_URL="$MCP_URL" TOKEN="$token" PATH_CFG="$path" \
  python3 - <<'PY'
import json, os
client, name = os.environ["CLIENT"], os.environ["SERVER_NAME"]
url, token, path = os.environ["MCP_URL"], os.environ["TOKEN"], os.environ["PATH_CFG"]
with open(path) as f:
    text = f.read().strip()
    try:
        data = json.loads(text) if text else {}
    except json.JSONDecodeError:
        raise SystemExit(f"{path}: не похоже на JSON — поправьте вручную")
if client == "claude-desktop":
    entry = {"command": "npx",
             "args": ["-y", "mcp-remote", url, "--header", "Authorization:${AUTH}"],
             "env": {"AUTH": f"Bearer {token}"}}
else:
    entry = {"url": url, "headers": {"Authorization": f"Bearer {token}"}, "disabled": False}
    if client == "cline":
        entry["type"] = "streamableHttp"
data.setdefault("mcpServers", {})[name] = entry
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"✓ {name} → {path}")
PY
}

write_codex() {
  local path token; path="$(config_path codex)"; token="$2"
  mkdir -p "$(dirname "$path")"; touch "$path"
  if grep -q "^\[mcp_servers\.${SERVER_NAME}\]" "$path"; then
    printf '! блок [mcp_servers.%s] уже есть в %s — обновите url/token вручную\n' "$SERVER_NAME" "$path"
  else
    printf '\n[mcp_servers.%s]\nurl = "%s"\nbearer_token_env_var = "LIPSYNC_TOKEN"\n' "$SERVER_NAME" "$MCP_URL" >> "$path"
    printf '✓ %s → %s\n' "$SERVER_NAME" "$path"
  fi
  printf 'export LIPSYNC_TOKEN="%s"   # в ~/.zshrc или ~/.bashrc\n' "$token"
}

claude_code_cmd() {
  printf 'claude mcp add --transport http --scope user %s %s --header "Authorization: Bearer %s"\n' \
    "$SERVER_NAME" "$MCP_URL" "$1"
}

print_all() {
  local token="${1:-ВАШ_ТОКЕН}"
  cat <<EOF
MCP URL: $MCP_URL

# Cline (VS Code / JetBrains) — cline_mcp_settings.json
{
  "mcpServers": {
    "$SERVER_NAME": {
      "type": "streamableHttp",
      "url": "$MCP_URL",
      "headers": { "Authorization": "Bearer $token" },
      "disabled": false
    }
  }
}

# Cursor — ~/.cursor/mcp.json
{ "mcpServers": { "$SERVER_NAME": { "url": "$MCP_URL", "headers": { "Authorization": "Bearer $token" } } } }

# Claude Code
$(claude_code_cmd "$token")

# Claude Desktop — claude_desktop_config.json (нужен Node.js: идёт через mcp-remote)
{
  "mcpServers": {
    "$SERVER_NAME": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "$MCP_URL", "--header", "Authorization:\${AUTH}"],
      "env": { "AUTH": "Bearer $token" }
    }
  }
}

# Codex — ~/.codex/config.toml
[mcp_servers.$SERVER_NAME]
url = "$MCP_URL"
bearer_token_env_var = "LIPSYNC_TOKEN"
EOF
}

usage() { sed -n '1,20p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; }

cmd="${1:-print}"
case "$cmd" in
  print|snippets)  print_all "${2:-}" ;;
  cline|cursor|claude-desktop)
    token="${2:-${LIPSYNC_TOKEN:-}}"
    [ -n "$token" ] || die "нужен токен: $0 $cmd vl_XXXX (или \$LIPSYNC_TOKEN)"
    write_json "$cmd" "$(config_path "$cmd")" "$token" ;;
  codex)
    token="${2:-${LIPSYNC_TOKEN:-}}"
    [ -n "$token" ] || die "нужен токен: $0 codex vl_XXXX (или \$LIPSYNC_TOKEN)"
    write_codex codex "$token" ;;
  claude-code)
    token="${2:-${LIPSYNC_TOKEN:-}}"
    [ -n "$token" ] || die "нужен токен: $0 claude-code vl_XXXX (или \$LIPSYNC_TOKEN)"
    claude_code_cmd "$token" ;;
  -h|--help|help) usage ;;
  *) die "неизвестная команда: $cmd (см. --help)" ;;
esac
