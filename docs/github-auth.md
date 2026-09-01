# GitHub authentication: scoped PATs and a signing-only SSH key

This guide documents a least-privilege GitHub setup for a shared or unattended
development Mac. It intentionally contains placeholders instead of account names,
organization names, token values, key fingerprints, or machine-specific paths.

The design separates three concerns:

- **Repository access** uses fine-grained personal access tokens (PATs) over HTTPS.
- **Commit identity** uses an SSH key registered with GitHub as a signing key only.
- **GitHub CLI login** is managed separately by `gh` and does not select Git's PATs.

The signing key grants no repository access. PATs are limited to one resource owner
and should expire on a deliberate rotation schedule.

## Fine-grained PAT permissions

For normal developer access, grant these three repository permissions:

- `Contents: Read and write`
- `Pull requests: Read and write`
- `Metadata: Read-only` (automatically enabled)

Add these optional permissions when the workflow needs them:

- `Issues: Read and write`
- `Actions: Read and write`
- `Workflows: Read-only`
- `Checks: Read-only`

Leave all other repository and organization permissions at **No access** unless a
specific workflow requires them. Prefer selected repositories over all repositories,
and use an expiration period that will actually be rotated, such as 90 days.

A fine-grained PAT belongs to exactly one resource owner. Create separate tokens for
an organization and a personal account. Both tokens may authenticate the same
GitHub login; the separation is about which resource owner and repositories each
token can access.

## Machine-local Git configuration

Keep host-specific configuration in `~/.gitconfig.local` with mode `600`. The shared
dotfiles `gitconfig` includes it:

```gitconfig
[include]
    path = ~/.gitconfig.local
```

For an unattended Mac, keep work and personal PATs in separate private credential
files. The empty `helper` value resets the inherited keychain helper for that URL;
the following value selects the matching dedicated store:

```gitconfig
[credential "https://github.com"]
    helper = osxkeychain

[credential "https://github.com/<org>"]
    helper =
    helper = store --file ~/.config/git/work-credentials
    username = <github-user>-work

[credential "https://github.com/<github-user>"]
    helper =
    helper = store --file ~/.config/git/personal-credentials
    username = <github-user>-personal

[user]
    signingkey = ~/.ssh/id_ed25519.pub
```

| Routing dimension | Work | Personal |
|---|---|---|
| GitHub resource owner | `<org>` | `<github-user>` |
| HTTPS URL prefix | `github.com/<org>/` | `github.com/<github-user>/` |
| Local username label | `<github-user>-work` | `<github-user>-personal` |
| Private helper file | `work-credentials` | `personal-credentials` |
| Commit author identity | Configured separately | Configured separately |

The filenames and username suffixes are examples. Resource-owner-specific names are
equally valid as long as the URL rule, helper path, and stored username agree.

Both credentials are plaintext at rest and readable by processes running as that
macOS user (and by `root`). Protect `~/.config/git` with mode `700`, protect each
credential file with mode `600`, scope each PAT narrowly, and never sync or commit
either file. This trade-off avoids an interactive login-keychain unlock after an
unattended restart. The generic `osxkeychain` entry remains only as a fallback for
GitHub owners that have no more-specific rule.

The resource-owner suffixes are local labels that make it obvious which credential
Git selected. GitHub authenticates the PAT rather than requiring the label to equal
the account login.

The resource-owner path match is case-sensitive even though GitHub repository URLs
are case-insensitive. Preserve the owner's canonical capitalization in both the
credential subsection and clone URL. Otherwise Git falls back to the generic
credential rule and may prompt with the wrong username.

This routing applies only to HTTPS remotes. Check `git remote -v` and explicitly
convert an SSH remote when PAT routing is intended:

```sh
git remote set-url origin https://github.com/<owner>/<repo>.git
```

Never commit `~/.gitconfig.local`, `~/.config/git/*-credentials`, a PAT, a keychain
export, or a private SSH key.

## Store the PATs

Create both private stores first:

```sh
umask 077
mkdir -p ~/.config/git
chmod 700 ~/.config/git
touch ~/.config/git/work-credentials ~/.config/git/personal-credentials
chmod 600 ~/.config/git/work-credentials ~/.config/git/personal-credentials
```

Invoke `credential-store` directly for each PAT. Enter the fields shown and finish
with a blank line. Pasting the token interactively keeps it out of shell history.

Work token:

```sh
git credential-store --file ~/.config/git/work-credentials store
```

```text
protocol=https
host=github.com
username=<github-user>-work
password=<paste-work-pat>

```

Personal token:

```sh
git credential-store --file ~/.config/git/personal-credentials store
```

```text
protocol=https
host=github.com
username=<github-user>-personal
password=<paste-personal-pat>

```

If a temporary plaintext input file already contains those four fields, redirect it
to the matching store instead of pasting:

```sh
git credential-store --file ~/.config/git/work-credentials store \
  < /path/to/work-credential-input

git credential-store --file ~/.config/git/personal-credentials store \
  < /path/to/personal-credential-input
```

Do not send a work token to the personal store or vice versa. After verification,
remove the temporary input files so the PAT does not remain in an unnecessary
second plaintext location.

## Agent access boundary

Codex, Claude Code, and other agents running as the same macOS user can technically
read these plaintext stores. Treat instruction files as guardrails, not as an
access-control boundary:

- Agents may use normal `git` commands and let the configured helper supply a PAT.
- Agents must not read credential files or run `git credential fill`/`get`.
- Agents must not extract a Git PAT into `GH_TOKEN`, a command, a prompt, or a log.
- Agents must not run `gh auth setup-git` or modify credential routing unless the
  user explicitly requests that exact change.
- A human should enter, rotate, and revoke PATs. Use a restricted OS account or a
  secrets broker when instructions alone are not a sufficient security boundary.

## Verify owner routing and access

Inspect Git's routing without printing either secret:

```sh
git config --get-urlmatch credential.helper \
  https://github.com/<org>/<private-work-repo>
git config --get-urlmatch credential.username \
  https://github.com/<org>/<private-work-repo>

git config --get-urlmatch credential.helper \
  https://github.com/<github-user>/dotfiles
git config --get-urlmatch credential.username \
  https://github.com/<github-user>/dotfiles
```

The work URL must resolve to `work-credentials` and `<github-user>-work`; the
personal URL must resolve to `personal-credentials` and
`<github-user>-personal`.

Verify each token against a private repository owned by that resource owner. A
public repository can succeed anonymously and is not a valid authentication test.

```sh
git ls-remote https://github.com/<org>/<private-repo>.git HEAD
git ls-remote https://github.com/<github-user>/<private-repo>.git HEAD
```

For a public personal repository, a push dry-run tests the authenticated write path
without updating branches, tags, commits, or files on GitHub:

```sh
git -C /path/to/personal-repo push --dry-run origin HEAD:main
```

A `non-fast-forward` dry-run rejection means authentication reached branch
validation but the local branch must be synchronized. Do not force-push merely to
make this check pass.

Organization policy may leave a new fine-grained PAT pending until an owner approves
it. Approval and repository selection do not prove that the token has `Contents`
access. If clone or fetch returns `403`, test the permission directly:

```sh
read -s PAT
printf '\n'
GH_TOKEN="$PAT" gh api -i repos/<org>/<private-repo>/contents/
unset PAT
```

`HTTP 403` together with `X-Accepted-GitHub-Permissions: contents=read` means the PAT
needs at least `Contents: Read-only`; this guide uses `Contents: Read and write` for
developer access.

## Configure commit signing

The PAT selected for a remote does not set commit authorship. Configure the author
name and a GitHub-verified email independently. For occasional exceptions, use
repository-local values:

```sh
git config --local user.name '<name>'
git config --local user.email '<verified-email>'
```

If work and personal repositories live under stable top-level directories, use
conditional includes in the machine-local config instead:

```gitconfig
[includeIf "gitdir:~/src/work/"]
    path = ~/.gitconfig.work

[includeIf "gitdir:~/src/personal/"]
    path = ~/.gitconfig.personal
```

Keep the corresponding identity files mode `600` and out of public dotfiles when
they contain real names, email addresses, or machine-specific key paths. A single
signing key may be used for both identities when it belongs to the same GitHub
account; separate keys are optional rather than required for PAT separation.

Generate or reuse an Ed25519 key and load it into the macOS keychain-backed agent:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Register the public key in GitHub under **Settings → SSH and GPG keys** as a
**Signing Key**, not an Authentication Key. Pinning `user.signingkey` prevents Git
from selecting a different key when the agent contains multiple identities.

Verify a signed commit:

```sh
git log -1 --format='%G? %GS'
```

`G` means Git considers the signature good. GitHub also requires the commit email to
be verified on the account before the web UI displays **Verified**.

## Optional SSH-over-HTTPS health checks

Repository access in this design uses HTTPS and PATs. If SSH health checks are still
useful on networks that block outbound port 22, route GitHub SSH through port 443:

```sshconfig
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519
```

The corresponding `known_hosts` entry must be keyed to `[ssh.github.com]:443`. Keep
the key registered as signing-only; `ssh -T git@github.com` is then only a transport
and host-key check, not the repository authentication path.

Do not add a global `url.insteadOf` rule that silently rewrites SSH GitHub URLs to
HTTPS. Convert repository remotes explicitly instead:

```sh
git remote set-url origin https://github.com/<owner>/<repo>.git
```

## GitHub CLI authentication

`gh` authentication is separate from Git's resource-owner credential routing:

```sh
gh auth login --hostname github.com --git-protocol https
gh auth status
gh api user --jq .login
```

`gh` maintains a hostname-level login and does not automatically choose
`work-credentials` or `personal-credentials` based on a repository URL. When both
PATs authenticate the same GitHub user, keep one explicit `gh` login for general CLI
use and let Git's URL rules handle repository transport. A human or approved secrets
broker may supply `GH_TOKEN` for an owner-specific `gh` operation; an agent must not
retrieve it from Git's credential store.

Do not run `gh auth setup-git` when preserving the split per-owner credential-helper
design above, because it can replace the intended Git helper routing. A fine-grained
token can also appear to fail during a GitHub service incident; check GitHub Status
before changing a token that was configured correctly.

### Refresh the gh login from a credential store

`gh` configuration lives in this repository's `gh/` directory, which is
gitignored because `hosts.yml` holds the CLI token. `GH_CONFIG_DIR` is exported
in `bashrc` (sourced by both bash and zsh startup) so interactive and
non-interactive shells — including agent harness shells — resolve the same
login instead of falling back to a stale `~/.config/gh`.

When `gh auth status` reports an invalid or expired token, a human runs:

```sh
~/dotfiles/scripts/gh-auth-refresh.sh                                 # personal store (default)
~/dotfiles/scripts/gh-auth-refresh.sh ~/.config/git/work-credentials  # work store
```

The script pipes the PAT from the selected Git credential store into
`gh auth login --with-token` without displaying it, so `gh` reuses the same PAT
as Git's HTTPS remotes. Rotating a PAT therefore means: update the credential
store (see "Store the PATs"), then run the refresh script. This remains a
human-run step — agents must not invoke it or read the store (see "Agent
access boundary").

## Restart verification

After restarting the machine, verify both access and signing again:

```sh
gh auth status
git ls-remote https://github.com/<org>/<private-repo>.git HEAD
git config --get-urlmatch credential.helper \
  https://github.com/<github-user>/dotfiles
git -C /path/to/personal-repo push --dry-run origin HEAD:main
stat -f '%Lp %Su %N' ~/.config/git/*-credentials
git log -1 --format='%G? %GS'
```

Credential files should report mode `600`. The personal dry-run may still report
`non-fast-forward` when the local branch is behind; that is a synchronization issue,
not a credential-store failure.
