# Tailscale SSH for a headless Mac mini

This guide describes the SSH access path used by the headless Mac mini. It is a
public-safe template: tailnet names, account emails, device names, Tailscale IPs,
MagicDNS suffixes, and ACL repository locations stay machine-local.

## Architecture

```text
Authorized tailnet device
    → encrypted Tailscale connection
    → tailscaled's built-in SSH server
    → local macOS account
```

The Mini deliberately uses **Tailscale SSH only**:

- macOS **Remote Login is off**.
- `com.openssh.sshd` is disabled and macOS has no port-22 listener.
- Tailscale authenticates the connecting tailnet identity.
- No inbound router port-forward is required.
- Local `authorized_keys` entries are not required for this path.

This removes the second, password-or-key-authenticated SSH server that macOS Remote
Login would otherwise expose to the local network.

## Boot-persistent daemon

Install the Homebrew CLI build rather than relying on the sandboxed GUI build for
the SSH server:

```sh
brew install tailscale
sudo brew services start tailscale
sudo tailscale up --ssh --accept-routes
```

The resulting system service is:

```text
/Library/LaunchDaemons/homebrew.mxcl.tailscale.plist
```

It should run as root with `RunAtLoad` and `KeepAlive`, allowing Tailscale SSH to
return during boot before a user opens an application.

Verify:

```sh
sudo launchctl print system/homebrew.mxcl.tailscale |
  grep -E 'state =|pid =|runs =|last exit code'

tailscale status
tailscale debug prefs | grep -E 'RunSSH|WantRunning|CorpDNS|RouteAll'
```

Expected values include a running daemon, `RunSSH: true`, and
`WantRunning: true`.

## Device enrollment and key expiry

Complete the Tailscale login flow and enable MagicDNS in the tailnet. Record the
actual device name and MagicDNS name only in machine-local notes or SSH config.

For an unattended server, disable device key expiry immediately after enrollment:

1. Open the Tailscale admin console.
2. Open **Machines** and select the Mini.
3. Choose **Disable key expiry**.
4. Confirm the machine displays **Expiry disabled**.

Disabling expiry improves availability but makes prompt device removal important if
the Mini is lost, retired, or compromised.

## Access controls

Keep the SSH rule least-privileged:

- Source: only the owner or explicitly approved administration devices.
- Destination: only the Mini.
- Users: only the required local macOS account; allow `root` only when remote
  administration genuinely needs it.
- Action: `accept` for unattended automation. An `action: check` rule can require
  an interactive reauthorization that GUI agents cannot complete.

If the admin console says the policy is externally managed, edit the repository or
infrastructure configuration that owns the policy. Do not loosen a general network
ACL to work around an SSH-rule problem.

A schematic rule looks like this; substitute selectors appropriate for the tailnet:

```json
{
  "ssh": [
    {
      "action": "accept",
      "src": ["<approved-source-selector>"],
      "dst": ["<mini-selector>"],
      "users": ["<macos-user>", "root"]
    }
  ]
}
```

The `root` mapping is optional. Confirm both allowed and denied identities when the
policy changes.

## Client SSH config

Keep real hostnames and usernames in `~/.ssh/config`, not in a public repository:

```sshconfig
Host mini
    HostName <mini-magicdns-name>
    User <macos-user>
    ConnectTimeout 10
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Then verify resolution and non-interactive access:

```sh
tailscale ping <mini-magicdns-name>
ssh -o BatchMode=yes mini 'whoami; hostname'
```

A local SSH alias such as `mini` is not automatically a Tailscale DNS name.
`tailscale ping mini` works only if `mini` is itself resolvable through DNS; otherwise
use the full MagicDNS name or Tailscale IP.

## Disable macOS Remote Login

After Tailscale SSH works, disable the ordinary macOS SSH server:

```sh
sudo systemsetup -f -setremotelogin off
```

Verify locally or through an existing Tailscale SSH connection:

```sh
sudo systemsetup -getremotelogin
sudo lsof -nP -iTCP:22 -sTCP:LISTEN
```

Expected results are `Remote Login: Off` and no macOS port-22 listener. Immediately
retest `ssh mini`; Tailscale SSH should continue to work.

## Which devices need Tailscale?

| Access path | Phone | Laptop | Mini |
|---|---:|---:|---:|
| SSH app directly from a phone | Required | Not involved | Required |
| Laptop SSH to Mini | Not involved | Required | Required |
| ChatGPT mobile direct Remote host | Not required | Not involved | Not required for that path |
| ChatGPT/Codex desktop SSH bridge | Not required | Required | Required |
| Claude Desktop SSH bridge | Not required | Required | Required |

ChatGPT direct Remote uses its own relay, but Tailscale remains the recovery and
administration path for the Mini.

## Reboot verification

After every change to Tailscale, macOS login, or power configuration, run a real
restart test:

```sh
ssh root@mini '/sbin/shutdown -r now'
```

After the Mini returns:

```sh
tailscale ping <mini-magicdns-name>
ssh mini 'uptime; whoami'
ssh root@mini '/usr/sbin/systemsetup -getremotelogin'
ssh root@mini 'lsof -nP -iTCP:22 -sTCP:LISTEN'
ssh root@mini \
  'launchctl print system/homebrew.mxcl.tailscale |
   grep -E "state =|pid =|runs =|last exit code"'
```

A normal restart verifies launch configuration. A controlled power-loss test is
still required to verify `autorestart=1`.
