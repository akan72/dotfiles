# Commit Instructions

Commit messages should be concise, just one sentence

# Pull Request Instructions

Create pull requests with the simple format

## Summary
<Describe the context for your change>

## Test Plan
<Evidence that the PR is working, include screenshots, and the CLI commands that you ran>

# Code Formatting Instructions

Single-line commands or code within a sentence should be wrapped in backticks

Multi-line commands or code should use fenced code blocks with triple backticks

# Git Credential Safety

GitHub HTTPS authentication may be routed by URL through machine-local credential
helpers. Use normal Git commands and let the configured helper supply credentials.

- Never ask for, read, display, copy, log, or inspect a token or credential file.
- Never run `git credential fill`, `git credential get`, or an equivalent helper
  command that returns a secret.
- Never extract a Git credential into `GH_TOKEN`, a command, a prompt, or a log.
- Never run `gh auth setup-git` or modify credential routing unless the user asks
  for that exact change.
- Never put credentials or machine-local authentication files in a repository.

Before a network Git operation, inspect the remote and selected routing without
reading a secret:

```sh
remote="$(git remote get-url origin)"
git config --get-urlmatch credential.helper "$remote"
git config --get-urlmatch credential.username "$remote"
```

Stop and ask the user if the expected helper or username is missing. Do not bypass a
missing include or repair credentials autonomously.

# Git Workflow Safety

- Inspect `git status --short` before editing or staging.
- Stage explicit files; do not use `git add .`.
- Do not commit or push unless the user explicitly requests it.
- Fetch and inspect divergence before pushing.
- Never force-push unless the user explicitly approves it after the risk is stated.
- Treat a dry-run `non-fast-forward` rejection as a synchronization issue, not an
  authentication failure.
- Verify commit name, email, and signing identity separately from PAT routing.
