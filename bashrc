# ----
# Basics

# Shared config (aliases, exports, consolidated PATH) used by both bash and zsh
[ -f "$HOME/.shared.sh" ] && . "$HOME/.shared.sh"

# ----
# bash-specific

# Terraform completion
if [ -n "$BASH_VERSION" ]; then
  complete -C /opt/homebrew/bin/terraform terraform
fi
