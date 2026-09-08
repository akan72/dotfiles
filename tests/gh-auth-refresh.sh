#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/gh-refresh-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/bin" "$test_root/home/.config/git"
# A synthetic value, never a real credential. Stub only the external login.
printf 'https://fixture:synthetic-value@github.com\n' > "$test_root/home/.config/git/personal-credentials"
cat > "$test_root/bin/gh" <<'STUB'
#!/bin/sh
set -eu
test "$GH_CONFIG_DIR" = "$HOME/.config/gh"
case "$*" in
  'auth login --hostname github.com --with-token')
    test "$(cat)" = synthetic-value
    ;;
  'auth status') ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$test_root/bin/gh"
env -i HOME="$test_root/home" PATH="$test_root/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$test_root/home/dotfiles" \
  sh "$repo/scripts/gh-auth-refresh.sh"
for shell in bash zsh; do
  env -i HOME="$test_root/home" PATH=/usr/bin:/bin \
    "$shell" -c '. "$1/shared.sh"; test "$GH_CONFIG_DIR" = "$HOME/.config/gh"' test "$repo"
done
test ! -e "$test_root/home/dotfiles/gh"
echo 'PASS refresh and shared shells use external gh configuration'
