#!/bin/bash

input=$(cat)

# Single jq call for all fields (TSV so display_name can contain spaces)
IFS=$'\t' read -r model_name current_dir context_size current_tokens session_cost lines_added lines_removed <<< "$(echo "$input" | jq -r '[
    (.model.display_name // "?"),
    (.workspace.current_dir // "."),
    (.context_window.context_window_size // 200000),
    ((.context_window.current_usage.input_tokens // 0)
      + (.context_window.current_usage.cache_creation_input_tokens // 0)
      + (.context_window.current_usage.cache_read_input_tokens // 0)),
    (.cost.total_cost_usd // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0)
] | @tsv')"

# Context percentage
if [ "$context_size" -gt 0 ] 2>/dev/null; then
    context_percent=$((current_tokens * 100 / context_size))
else
    context_percent=0
fi

# Progress bar (15 chars wide)
bar_width=15
filled=$((context_percent * bar_width / 100))
[ "$filled" -gt "$bar_width" ] && filled=$bar_width
empty=$((bar_width - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

dir_name=$(basename "$current_dir")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

cd "$current_dir" 2>/dev/null || cd /

# Git info — branch + file count from git, line deltas from Claude stdin
git_info=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    total_files=$(git status --porcelain 2>/dev/null | wc -l | xargs)

    if [ "${total_files:-0}" -gt 0 ] || [ "${lines_added:-0}" -gt 0 ] || [ "${lines_removed:-0}" -gt 0 ]; then
        git_info=" ${BLUE}(${RED}${branch}${NC} ${YELLOW}|${NC} ${GRAY}${total_files} files${NC}"
        [ "${lines_added:-0}" -gt 0 ] && git_info="${git_info} ${GREEN}+${lines_added}${NC}"
        [ "${lines_removed:-0}" -gt 0 ] && git_info="${git_info} ${RED}-${lines_removed}${NC}"
        git_info="${git_info} ${BLUE})${NC}"
    else
        git_info=" ${BLUE}(${branch})${NC}"
    fi
fi

# Cost (jq gives "0" when absent; skip display in that case)
cost_info=""
if [ "$session_cost" != "0" ] && [ -n "$session_cost" ]; then
    cost_formatted=$(printf "%.4f" "$session_cost" 2>/dev/null)
    [ -n "$cost_formatted" ] && cost_info=" ${GRAY}[\$${cost_formatted}]${NC}"
fi

context_info="${GRAY}${bar}${NC} ${context_percent}%"

echo -e "${BLUE}${dir_name}${NC} ${GRAY}|${NC} ${CYAN}${model_name}${NC} ${GRAY}|${NC} ${context_info}${git_info:+ ${GRAY}|${NC}}${git_info}${cost_info}"
