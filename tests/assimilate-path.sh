#!/usr/bin/env bash

set -eu

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$test_dir/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/assimilate-path.XXXXXX")
test_home=$(CDPATH='' cd -- "$test_home" && pwd -P)
codex_marker="$test_home/codex-called"
mkdir "$test_home/bin"
mkdir "$test_home/.config"
printf 'existing Bun fixture policy\n' > "$test_home/.config/.bunfig.toml"
cat > "$test_home/bin/brew" <<'BREW'
#!/usr/bin/env sh
if [ -n "${TEST_BREW_LOG:-}" ] && [ "${1:-}" = bundle ]; then
  printf '%s|%s|%s|%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-}" "${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:-}" "${HOMEBREW_NO_INSTALL_CLEANUP:-}" "$*" >> "$TEST_BREW_LOG"
  echo 'FIXTURE_HOMEBREW_ROUTINE_NOISE'
fi
exit 0
BREW
chmod +x "$test_home/bin/brew"

cleanup() {
  rm -rf "$test_home"
}
trap cleanup EXIT HUP INT TERM

set +e
HOME="$test_home" \
  PATH="$test_home/bin:$test_dir/fixtures/bin:$PATH" \
  TEST_CODEX_MARKER="$codex_marker" \
  TEST_BREW_LOG="$test_home/brew.log" \
  bash "$repo_root/assimilate.sh" >"$test_home/console.log" 2>&1
status=$?
set -e

if [ "$status" -ne 1 ]; then
  echo "expected assimilate.sh to reach the stubbed codex command, got status $status" >&2
  exit 1
fi

if [ ! -f "$codex_marker" ]; then
  echo "expected the checkout's Codex sync script to invoke codex" >&2
  exit 1
fi

test "$(readlink "$test_home/.claude/CLAUDE.md")" = "$repo_root/agent-instructions.md"
test "$(readlink "$test_home/.codex/AGENTS.md")" = "$repo_root/agent-instructions.md"
test "$(readlink "$test_home/.claude/statusline.sh")" = "$repo_root/claude/statusline.sh"
test "$(readlink "$test_home/.bunfig.toml")" = "$repo_root/.bunfig.toml"
test "$(readlink "$test_home/.config/.bunfig.toml")" = "$repo_root/.bunfig.toml"
bun_backup=$(find "$test_home/backups" -type f -name '.bunfig.toml.*')
test "$(cat "$bun_backup")" = 'existing Bun fixture policy'
test -f "$test_home/.claude/settings.json"
test ! -L "$test_home/.claude/settings.json"
test "$(jq -r '.outputStyle' "$test_home/.claude/settings.json")" = "Concise"

expected_args='app-server --strict-config --listen stdio://'
actual_args=$(sed -n '1p' "$codex_marker")
if [ "$actual_args" != "$expected_args" ]; then
  echo "expected Codex validator arguments $expected_args, got $actual_args" >&2
  exit 1
fi

grep -Fq '[01/09] Existing installation preflight' "$test_home/console.log"
grep -Fq 'FAILED: Agent settings (exit 1)' "$test_home/console.log"
grep -Fq 'Full log:' "$test_home/console.log"
if grep -Fq 'FIXTURE_HOMEBREW_ROUTINE_NOISE' "$test_home/console.log"; then exit 1; fi
if [ "$(uname -s)" = Darwin ]; then grep -Fq '1|1|1|bundle check' "$test_home/brew.log"; fi
# Full command output is available only when explicitly requested.
set +e
HOME="$test_home" PATH="$test_home/bin:$test_dir/fixtures/bin:$PATH" \
  TEST_CODEX_MARKER="$codex_marker" TEST_BREW_LOG="$test_home/brew.log" \
  bash "$repo_root/assimilate.sh" --verbose >"$test_home/verbose.log" 2>&1
verbose_status=$?
set -e
test "$verbose_status" = 1
test "$(find "$test_home/backups" -type f -name '.bunfig.toml.*')" = "$bun_backup"
test "$(readlink "$test_home/.config/.bunfig.toml")" = "$repo_root/.bunfig.toml"
if [ "$(uname -s)" = Darwin ]; then grep -Fq 'FIXTURE_HOMEBREW_ROUTINE_NOISE' "$test_home/verbose.log"; fi
# The read-only mode creates logs but never links configuration or calls package managers.
mkdir "$test_home/check-home"
HOME="$test_home/check-home" PATH="$test_home/bin:$test_dir/fixtures/bin:$PATH" \
  bash "$repo_root/assimilate.sh" --check >"$test_home/check.log" 2>&1
grep -Fq '[01/01] Existing installation preflight' "$test_home/check.log"
test ! -e "$test_home/check-home/.shared.sh"
test ! -e "$test_home/check-home/.oh-my-zsh"
# Both modes catch all unmanaged CLI installations before links, packages or settings.
mkdir -p "$test_home/cli-home/.local/bin" "$test_home/cli-home/.local/share/google-cloud-sdk"
printf 'unmanaged delta\n' > "$test_home/cli-home/.local/bin/delta"
printf 'unmanaged gcloud\n' > "$test_home/cli-home/.local/share/google-cloud-sdk/fixture"
for mode in regular check; do
  set --; if [ "$mode" = check ]; then set -- --check; fi
  if HOME="$test_home/cli-home" TEST_BREW_LOG="$test_home/cli-brew-called" \
    TEST_CODEX_MARKER="$test_home/cli-codex-called" \
    PATH="$test_home/bin:$test_dir/fixtures/bin:$PATH" bash "$repo_root/assimilate.sh" "$@" >"$test_home/cli-$mode.log" 2>&1; then exit 1; fi
  grep -Fq "unmanaged installation: $test_home/cli-home/.local/bin/delta" "$test_home/cli-$mode.log"
  grep -Fq "unmanaged installation: $test_home/cli-home/.local/share/google-cloud-sdk" "$test_home/cli-$mode.log"
  grep -Fq 'FAILED: Existing installation preflight' "$test_home/cli-$mode.log"
  if grep -Fq 'Assimilation Successful!' "$test_home/cli-$mode.log"; then exit 1; fi
  test ! -e "$test_home/cli-home/.shared.sh"
  test ! -e "$test_home/cli-home/.gitconfig"
  test ! -e "$test_home/cli-home/.claude"
  test ! -e "$test_home/cli-home/backups"
  test ! -e "$test_home/cli-brew-called"
  test ! -e "$test_home/cli-codex-called"
  test "$(cat "$test_home/cli-home/.local/bin/delta")" = 'unmanaged delta'
  test "$(cat "$test_home/cli-home/.local/share/google-cloud-sdk/fixture")" = 'unmanaged gcloud'
done
if grep -Fq 'Assimilation Successful!' "$test_home/check.log"; then exit 1; fi
# A rejected existing checkout stops the full install before links/Homebrew/settings.
mkdir "$test_home/bad-home"
git -c core.hooksPath=/dev/null init -q "$test_home/bad-home/.oh-my-zsh"
git -C "$test_home/bad-home/.oh-my-zsh" remote add origin https://example.invalid/wrong.git
if HOME="$test_home/bad-home" TEST_BREW_LOG="$test_home/should-not-run" \
  PATH="$test_home/bin:$test_dir/fixtures/bin:$PATH" bash "$repo_root/assimilate.sh" >"$test_home/bad.log" 2>&1; then exit 1; fi
grep -Fq 'FAILED: Existing installation preflight' "$test_home/bad.log"
test ! -e "$test_home/bad-home/.shared.sh"
test ! -e "$test_home/should-not-run"
# Exercise the production dispatcher with inert stages, including its final banner.
sed '/^# Run the reviewed setup phases/,$d' "$repo_root/assimilate.sh" > "$test_home/dispatch.sh"
cat >> "$test_home/dispatch.sh" <<'STAGES'
for phase in installation_preflight link_config package_policy sync_agents python_and_hooks omz_checkout install_clis tmux_checkouts install_nvim; do
  eval "function $phase () { :; }"
done
if [ "${TEST_DISPATCH_FAILURE:-0}" = 1 ]; then
  function install_clis () { return 23; }
fi
STAGES
sed -n '/^# Run the reviewed setup phases/,$p' "$repo_root/assimilate.sh" >> "$test_home/dispatch.sh"
HOME="$test_home/dispatch-home" bash "$test_home/dispatch.sh" > "$test_home/success.log" 2>&1
grep -Fxq 'Assimilation Successful!' "$test_home/success.log"
HOME="$test_home/dispatch-home" bash "$test_home/dispatch.sh" --check > "$test_home/dispatch-check.log" 2>&1
if grep -Fq 'Assimilation Successful!' "$test_home/dispatch-check.log"; then exit 1; fi
set +e
HOME="$test_home/dispatch-home" TEST_DISPATCH_FAILURE=1 bash "$test_home/dispatch.sh" > "$test_home/dispatch-fail.log" 2>&1
dispatch_status=$?
set -e
test "$dispatch_status" = 23
if grep -Fq 'Assimilation Successful!' "$test_home/dispatch-fail.log"; then exit 1; fi
# A failed stage retains its original status and never executes the next action.
set +e
(
  set -Ee
  exec 3>&1 4>&2
  LOG_DIR="$test_home/logger"
  mkdir "$LOG_DIR"
  # shellcheck disable=SC2034 # State is consumed by the extracted production functions.
  STEP_NUMBER=0 TOTAL_STEPS=1 VERBOSE=0
  eval "$(sed -n '/^function report_failure () {/,/^}/p' "$repo_root/assimilate.sh")"
  eval "$(sed -n '/^function run_step () {/,/^}/p' "$repo_root/assimilate.sh")"
  trap 'report_failure "$?"' ERR
  run_step 'fixture failure' bash -c 'echo useful-fixture-diagnostic >&2; exit 23'
  touch "$test_home/should-not-continue"
) >"$test_home/logger-console.log" 2>&1
logger_status=$?
set -e
if [ "$logger_status" != 23 ]; then cat "$test_home/logger-console.log" >&2; exit 1; fi
test ! -e "$test_home/should-not-continue"
grep -Fq 'FAILED: fixture failure (exit 23)' "$test_home/logger-console.log"
grep -Fq 'useful-fixture-diagnostic' "$test_home/logger-console.log"
echo "assimilate: checkout-relative paths, structured failures, quiet Homebrew policy and early checkout/CLI preflight passed"
