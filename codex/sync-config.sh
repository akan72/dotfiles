#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
managed_config="$script_dir/config.managed.toml"
codex_home=${CODEX_HOME:-"$HOME/.codex"}
dest_config="$codex_home/config.toml"
start_marker="# dotfiles-managed:start"
end_marker="# dotfiles-managed:end"
tables_start_marker="# dotfiles-managed-tables:start"
tables_end_marker="# dotfiles-managed-tables:end"
managed_keys="notify|model_reasoning_summary|model_verbosity|personality|approvals_reviewer|project_doc_fallback_filenames|project_doc_max_bytes"
managed_table_prefixes="desktop"

if [ ! -f "$managed_config" ]; then
  echo "Managed Codex config not found: $managed_config" >&2
  exit 1
fi

mkdir -p "$codex_home"

if [ -f "$dest_config" ]; then
  start_count=$(grep -Fxc "$start_marker" "$dest_config" || true)
  end_count=$(grep -Fxc "$end_marker" "$dest_config" || true)
  tables_start_count=$(grep -Fxc "$tables_start_marker" "$dest_config" || true)
  tables_end_count=$(grep -Fxc "$tables_end_marker" "$dest_config" || true)

  if [ "$start_count" -ne "$end_count" ] || [ "$start_count" -gt 1 ] ||
    [ "$tables_start_count" -ne "$tables_end_count" ] || [ "$tables_start_count" -gt 1 ]; then
    echo "Refusing to update malformed managed markers in $dest_config" >&2
    exit 1
  fi
fi

tmp_file=$(mktemp "$codex_home/.config.toml.XXXXXX")

cleanup() {
  if [ -n "${tmp_file:-}" ]; then
    rm -f "$tmp_file"
  fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

{
  printf '%s\n' "$start_marker"
  awk '
    /^[[:space:]]*\[/ { in_table = 1 }
    !in_table { print }
  ' "$managed_config"
  printf '%s\n\n' "$end_marker"

  if [ -f "$dest_config" ]; then
    awk \
      -v start_marker="$start_marker" \
      -v end_marker="$end_marker" \
      -v tables_start_marker="$tables_start_marker" \
      -v tables_end_marker="$tables_end_marker" \
      -v managed_keys="$managed_keys" \
      -v managed_table_prefixes="$managed_table_prefixes" '
        $0 == start_marker || $0 == tables_start_marker { in_managed = 1; next }
        in_managed && ($0 == end_marker || $0 == tables_end_marker) { in_managed = 0; next }
        in_managed { next }
        $0 ~ "^[[:space:]]*\\[(" managed_table_prefixes ")(\\.|\\])" { in_managed_table = 1; next }
        in_managed_table && /^[[:space:]]*\[/ { in_managed_table = 0 }
        in_managed_table { next }
        in_managed_array && /^[[:space:]]*\][[:space:]]*(#.*)?$/ { in_managed_array = 0; next }
        in_managed_array { next }
        /^[[:space:]]*\[/ { in_table = 1 }
        !in_table && $0 ~ "^[[:space:]]*(" managed_keys ")[[:space:]]*=" {
          if ($0 ~ "=[[:space:]]*\\[[^]]*$") { in_managed_array = 1 }
          next
        }
        !emitted && /^[[:space:]]*$/ { next }
        { emitted = 1; print }
      ' "$dest_config"
  fi

  printf '%s\n' "$tables_start_marker"
  awk '
    /^[[:space:]]*\[/ { in_table = 1 }
    in_table { print }
  ' "$managed_config"
  printf '%s\n' "$tables_end_marker"
} > "$tmp_file"

chmod 600 "$tmp_file"
mv "$tmp_file" "$dest_config"
tmp_file=

echo "> Synced managed Codex settings to $dest_config"
