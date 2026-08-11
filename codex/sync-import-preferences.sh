#!/usr/bin/env sh

set -eu

codex_home=${CODEX_HOME:-"$HOME/.codex"}
state_file="$codex_home/.codex-global-state.json"

if [ ! -f "$state_file" ]; then
  echo "> Skipped Codex import preferences; launch Codex and configure Claude Code import once"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to sync Codex import preferences" >&2
  exit 1
fi

selection_filter='.
  ["electron-persisted-atom-state"]
  ["external-agent-import-sync-state"]
  ["selection"]'

if ! jq -e "$selection_filter | type == \"object\"" "$state_file" >/dev/null; then
  echo "> Skipped Codex import preferences; configure Claude Code import once, then rerun assimilation"
  exit 0
fi

tmp_file=$(mktemp "$codex_home/.codex-global-state.json.XXXXXX")

cleanup() {
  if [ -n "${tmp_file:-}" ]; then
    rm -f "$tmp_file"
  fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

jq '
  .["electron-persisted-atom-state"]
   ["external-agent-import-sync-state"]
   ["selection"] |= (
    .chats = false
    | with_entries(
        if (.key | test("^SESSIONS:claude-code:")) then
          .value = false
        elif (.key | test("^(AGENTS_MD|CONFIG|SKILLS|COMMANDS|SUBAGENTS|HOOKS|PLUGINS|MCP_SERVER_CONFIG):claude-code:")) then
          .value = true
        else
          .
        end
      )
  )
' "$state_file" > "$tmp_file"

chmod 600 "$tmp_file"
mv "$tmp_file" "$state_file"
tmp_file=

echo "> Synced Claude Code imports without chat sessions"
