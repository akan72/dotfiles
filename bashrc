# shellcheck shell=bash
# ----
# Basics

# Shared config (aliases, exports, consolidated PATH) used by both bash and zsh
# Assimilation links this trusted repository config; do not inspect live HOME during lint.
# shellcheck source=/dev/null
[ -f "$HOME/.shared.sh" ] && . "$HOME/.shared.sh"

# ----
# bash-specific

# Terraform completion
if [ -n "$BASH_VERSION" ]; then
  complete -C /opt/homebrew/bin/terraform terraform
fi
