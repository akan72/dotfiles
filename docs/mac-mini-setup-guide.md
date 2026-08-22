# Headless Mac mini development host

This guide provisions an Apple Silicon Mac mini as an unattended development host
for shell work, Codex, Claude Code, and ChatGPT mobile Remote mode.

It uses one deliberate access architecture:

- Tailscale SSH is the only SSH server.
- macOS Remote Login stays off.
- Tailscale starts as a root LaunchDaemon before user login.
- The Mini does not sleep and restarts after a power failure.
- Automatic login starts user-level GUI services after boot.
- Real hostnames, accounts, IP addresses, tokens, and key fingerprints remain
  machine-local.

See [tailscale-ssh.md](tailscale-ssh.md) for the detailed access and policy model and
[github-auth.md](github-auth.md) for GitHub credentials.

## Availability and security trade-off

Direct mobile control of a GUI application after a cold boot requires a logged-in
macOS user session. This setup therefore uses:

- FileVault off
- Automatic login for the dedicated development account
- ChatGPT configured to open at login

That maximizes unattended recovery but weakens protection against physical access.
Use it only when the Mini is kept in a trusted location. If physical security is
more important, enable FileVault and accept that someone must unlock the Mini after
a cold boot before GUI Remote mode becomes available.

Tailscale SSH itself starts before GUI login and remains the recovery path.

## 1. Initial physical setup

Complete the first macOS setup with a display and keyboard.

### Set stable names

Use names that do not reveal a person, company, or location:

```sh
sudo scutil --set HostName <mini-hostname>
sudo scutil --set LocalHostName <mini-hostname>
sudo scutil --set ComputerName '<friendly-name>'
```

Changing names later can change the label shown by ChatGPT Remote and the name
advertised to Tailscale, so document the mapping before changing an established host.

### Configure power

```sh
sudo pmset -a sleep 0
sudo pmset -a standby 0
sudo pmset -a disksleep 0
sudo pmset -a womp 1
sudo pmset -a autorestart 1
sudo pmset -a powernap 0
sudo pmset -a networkoversleep 0
```

Display sleep does not suspend the host and may remain enabled. Verify the effective
AC-power settings:

```sh
pmset -g custom
```

Expected values include `sleep 0`, `standby 0`, `disksleep 0`, `womp 1`, and
`autorestart 1`.

### Configure unattended login

In **System Settings → Users & Groups**, enable automatic login for the dedicated
development account. Automatic login requires FileVault to be off.

Verify:

```sh
fdesetup status
defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser
```

### Prefer Ethernet

Use wired Ethernet for an always-on host. Wi-Fi works, but roaming, interference,
access-point maintenance, and DHCP transitions add avoidable disconnects.

Check the active default interface:

```sh
route -n get default | grep interface
```

A changing local address does not affect the stable Tailscale IP or MagicDNS name.

## 2. Install platform tools

Install Apple's Command Line Tools and verify them:

```sh
xcode-select --install
xcode-select -p
clang --version
```

If the normal installer is unavailable, download the matching Command Line Tools
package from Apple's developer downloads site. Do not delete an existing toolchain
unless its installation is known to be corrupt.

Install Homebrew and add it to the Apple Silicon login-shell path:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew doctor
```

## 3. Configure Tailscale SSH

Install the Homebrew Tailscale build and start it as a system service:

```sh
brew install tailscale
sudo brew services start tailscale
sudo tailscale up --ssh --accept-routes
```

If the sandboxed Tailscale GUI build is installed, use its supported uninstaller
before configuring the Homebrew daemon. Do not leave two Tailscale daemons competing
for the same state.

In the admin console:

1. Give the device a neutral, stable name.
2. Disable key expiry for the unattended Mini.
3. Keep the SSH rule limited to approved identities and this destination.
4. Use `action: accept` when GUI agents require non-interactive SSH.
5. If Access Controls is locked as externally managed, edit the owning repository
   or infrastructure configuration rather than the web editor.

Verify the daemon and Tailscale SSH:

```sh
tailscale status
tailscale ip -4
tailscale debug prefs | grep -E 'RunSSH|WantRunning'
sudo launchctl print system/homebrew.mxcl.tailscale |
  grep -E 'state =|pid =|runs =|last exit code'
```

After Tailscale SSH works, disable ordinary macOS Remote Login:

```sh
sudo systemsetup -f -setremotelogin off
sudo systemsetup -getremotelogin
sudo lsof -nP -iTCP:22 -sTCP:LISTEN
```

The expected state is `Remote Login: Off` with no macOS port-22 listener.

## 4. Configure the administration laptop

Install and sign into Tailscale on the laptop. Add a machine-local SSH alias:

```sshconfig
Host mini
    HostName <mini-magicdns-name>
    User <macos-user>
    ConnectTimeout 10
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Protect the file and test both normal and privileged mappings:

```sh
chmod 600 ~/.ssh/config
tailscale ping <mini-magicdns-name>
ssh -o BatchMode=yes mini 'whoami; hostname'
ssh -o BatchMode=yes root@mini 'whoami; hostname'
```

Allow the `root` mapping in the Tailscale SSH policy only when it is needed for
administration. Do not add an SSH private key, PAT, password, or real infrastructure
identifier to the public dotfiles repository.

## 5. Install development agents

Install the required runtime and CLIs:

```sh
brew install node python
npm install -g @openai/codex @anthropic-ai/claude-code
```

Verify from a login shell, because desktop SSH integrations launch the remote user's
login shell:

```sh
zsh -lic 'command -v codex; codex --version; codex login status'
zsh -lic 'command -v claude; claude --version; claude auth status'
```

Complete each product's login flow on the Mini. Authentication and settings for a
standalone CLI belong to that Mini user account.

### Codex desktop over SSH

The Codex/ChatGPT desktop app on a laptop can add the `mini` SSH host and start a
Codex app server through the Mini's login shell.

This path requires:

- Laptop awake, online, and running the desktop app
- Tailscale running on the laptop and Mini
- `codex` available in the Mini's login-shell `PATH`

Tasks execute against the Mini's files, tools, and remote environment.

### ChatGPT mobile direct Remote host

Install the ChatGPT desktop app on the Mini. In
**Settings → Connections → Control this Mac or PC**, enable Remote mode and pair the
phone using the same ChatGPT account and workspace. See OpenAI's
[Remote connections guide](https://learn.chatgpt.com/docs/remote-connections) for
the current product requirements.

Add ChatGPT to **System Settings → General → Login Items → Open at Login**. A direct
mobile session then follows this path:

```text
ChatGPT mobile → OpenAI relay → ChatGPT app on Mini → local Codex
```

Tailscale is not required on the phone or for this relay path. Keep Tailscale running
on the Mini for recovery and SSH administration.

To avoid accidentally using the laptop bridge, select the Mini's connected-computer
entry on mobile. Verify the destination with:

```sh
hostname
whoami
pwd
```

### Claude Desktop over SSH

Claude Desktop on the laptop can use the same `mini` SSH alias. It deploys and runs
its own remote Claude Code CLI under the Mini user's home directory.

This path requires the laptop and Mini to remain connected through Tailscale. The
standalone `claude` login on the Mini and the Claude Desktop account are separate
authentication contexts; do not assume one replaces the other.

Claude Desktop may pause an idle remote session and reconnect later. An idle pause
is different from an SSH deployment failure.

## 6. Configure GitHub

Follow [github-auth.md](github-auth.md). Keep repository access and signing separate:

- Fine-grained PATs over HTTPS for clone, fetch, and push
- Signing-only SSH key for commit signatures
- Separate PATs for separate resource owners
- Separate mode-`600` work and personal credential files for unattended access
- URL-owner rules that route each repository to the correct credential file
- Separate `gh` authentication from Git's credential helpers

Test the work token against a private repository. For a public personal repository,
use `git push --dry-run`; an anonymous public read does not prove the personal PAT is
working. Configure commit name/email separately because PAT selection does not set
authorship.

## 7. Optional terminal persistence

Interactive commands launched directly under SSH normally end when the connection
dies. Use `tmux` for work that must survive laptop sleep or network transitions:

```sh
brew install tmux
tmux new -s work
```

Detach with `Ctrl-b d` and return with:

```sh
tmux attach -t work
```

Codex and Claude desktop-managed sessions have their own lifecycle and should not be
wrapped in a manually created `tmux` session unless their documentation explicitly
calls for it.

## 8. Final restart test

Restart through the already-verified Tailscale SSH path:

```sh
ssh root@mini '/sbin/shutdown -r now'
```

After the Mini returns, verify from the laptop:

```sh
tailscale ping <mini-magicdns-name>
ssh mini 'uptime; whoami'
ssh mini 'zsh -lic "codex login status; claude --version; gh auth status"'
ssh mini 'stat -f "%Lp %Su %N" ~/.config/git/*-credentials'
ssh mini 'git config --get-urlmatch credential.helper https://github.com/<org>/<repo>'
ssh mini 'git config --get-urlmatch credential.helper https://github.com/<github-user>/dotfiles'
ssh root@mini '/usr/sbin/systemsetup -getremotelogin'
ssh root@mini 'lsof -nP -iTCP:22 -sTCP:LISTEN'
ssh root@mini \
  'launchctl print system/homebrew.mxcl.tailscale |
   grep -E "state =|pid =|runs =|last exit code"'
```

Expected results:

- Tailscale answers and SSH connects without an interactive check.
- The console user is the configured automatic-login account.
- The Tailscale daemon has a new post-boot PID and no failed exit.
- macOS Remote Login is off and macOS has no port-22 listener.
- Codex, Claude, and both work/personal Git credential routes remain available.
- ChatGPT starts automatically.

Finally, close the laptop's ChatGPT app and start a mobile task against the Mini's
connected-computer entry. Run `hostname; whoami; pwd`. This proves direct mobile
Remote mode survived the restart rather than falling back to the laptop's SSH bridge.

A normal restart does not prove recovery from a power outage. If unattended power
recovery matters, perform one controlled power-loss test after backups are current.

## Troubleshooting

| Symptom | Check |
|---|---|
| `tailscale ping mini` says no such host | `mini` is only an SSH alias; use the full MagicDNS name or Tailscale IP |
| Tailscale is online but SSH times out | Check `RunSSH`, the externally managed SSH policy, and destination selectors |
| SSH asks for a Tailscale re-check | Replace `action: check` with approved `action: accept` policy where unattended access is intended |
| SSH works locally but not remotely | Confirm both devices are online in the same tailnet and use the Tailscale name/IP |
| Mobile Remote disappears after reboot | Confirm automatic login, ChatGPT Open at Login, and the paired account/workspace |
| Mobile Remote drops while the Mini stays awake | Prefer Ethernet and record the exact time for application/relay log review |
| Claude Desktop stalls while deploying | Verify plain `ssh mini`, remote internet access, disk space, and the deployed CLI path |
| `gh auth login` returns a transient 5xx | Check GitHub Status before changing a correctly scoped PAT |
| HTTPS clone returns `403` or prompts with the wrong username | Match the credential subsection to the resource owner's exact capitalization, confirm the expected helper and username with `git config --get-urlmatch`, verify repository approval, then test the PAT's Contents permission with the repository contents API |
| Git fetch succeeds but PAT may be missing | Test a private repository; public reads can succeed anonymously |
| Personal push dry-run returns `non-fast-forward` | Authentication reached branch validation; fetch and inspect divergence, preserve local changes, and synchronize without force-pushing |

## Public-repository safety

Safe to commit:

- Generic commands
- Placeholder SSH config
- Permission names
- Architecture and verification procedures

Keep out of the repository:

- PATs, credential-store files, OAuth files, cookies, or keychain exports
- `~/.codex/auth.json` or Claude authentication state
- SSH private keys
- Real tailnet names, MagicDNS suffixes, Tailscale IPs, emails, or ACL identities
- Remote enrollment databases
- Machine-local `~/.ssh/config` and `~/.gitconfig.local` values
