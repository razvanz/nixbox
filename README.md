# nixbox

MicroVM sandbox for running AI agents (eg: Claude Code with `--dangerously-skip-permissions`) in full isolation. Host protected by hypervisor boundary + egress filtering. Directories shared via virtiofs bind mounts. Supports Linux (cloud-hypervisor) and macOS on Apple Silicon (vfkit / Virtualization.framework).

Multiple VMs can run concurrently (up to 64), each with isolated slot-based networking. Mount your entire workspace (e.g. `~/workspace`) rather than a single project — this lets you switch between projects inside the VM without restarting it.

## Philosophy

- **Isolated** — KVM boundary. A compromised agent cannot reach the host.
- **Lightweight** — balloon memory, shared vCPUs, virtiofs. Feels like a shell, not a second machine.
- **Reproducible** — Nix-built image. Same config, same guest, every time.
- **Explicit** — secrets passed via `env`, mounts opted-in, write access deliberate.
- **Filtered** — egress controls prevent data exfiltration (`off` / `filtered` / `open`).
- **Composable** — plugins provide packages, mounts, domains, scripts. Stack them in your config.

## Prerequisites

### Linux

- KVM (`/dev/kvm`)
- [Nix](https://nixos.org/download/) with flakes enabled
- `dnsmasq`, `nftables`, `e2fsprogs` (for `mke2fs`), `virtiofsd`

### macOS (Apple Silicon)

- macOS 13+ (Ventura) with Virtualization.framework
- [Nix](https://nixos.org/download/) with flakes enabled
- `e2fsprogs` (for `mke2fs`)

## Install

```bash
nix profile install "git+ssh://git@github.com/razvanz/nixbox"
```

## Quick start

```bash
# 1. Initialize config at your workspace root
cd ~/workspace
nixbox init          # creates .nixbox/

# 2. Edit config
$EDITOR .nixbox/config.nix

# 3. Boot VM (auto-setup + auto-build on first run)
nixbox up

# 4. Connect
nixbox shell
# or run a command directly
nixbox run "cd ~/workspace/myproject && claude --dangerously-skip-permissions -p 'fix tests'"

# 5. Destroy when done
nixbox down
```

Subsequent `nixbox up` calls skip the build unless `.nixbox/config.nix` or nixbox itself changed.

## Config (`.nixbox/config.nix`)

```nix
{
  plugins = [ "claude-code" "aws" ];              # Built-in plugins (see below)
  name = "dev";
  resources.vcpus = 4;                            # Default: all host cores
  resources.memoryMB = 8192;                      # Default: half of host RAM, min 4GB (balloon)
  network.mode = "filtered";                      # "off" | "filtered" | "open"
  network.domains = [ "github.com" "npmjs.org" ]; # Additive — merged with plugin + base domains
  env = {
    GITHUB_TOKEN = builtins.getEnv "GITHUB_TOKEN";
  };
}
```

See `config.example.nix` for all fields.

## CLI commands

| Command | Purpose |
|---|---|
| `nixbox init` | Create `.nixbox/` directory in cwd |
| `nixbox up` | Start VM (auto-setup + auto-build if needed) |
| `nixbox down` | Destroy VM for current project |
| `nixbox shell` | SSH into VM (interactive) |
| `nixbox run <cmd>` | Run command in VM (non-interactive) |
| `nixbox mount <spec>` | Hot-plug bind mount |
| `nixbox unmount <target>` | Remove bind mount |
| `nixbox status` | Show running VM info |
| `nixbox config` | Print resolved project config |
| `nixbox doctor` | Check prerequisites and config |
| `nixbox setup` | Run one-time setup manually |
| `nixbox build [-f]` | Build VM runner manually (`-f` to force) |
| `nixbox <plugin> <cmd>` | Run a plugin command (e.g. `nixbox aws login`) |

## Networking

Three modes controlled by `network.mode`:

- **`open`** (default) — all traffic forwarded, no restrictions
- **`filtered`** — DNS allowlist + port-based firewall. Only domains in `network.domains` resolve (suffix-matched — `github.com` covers `api.github.com` etc.); only `network.ports` (default: 80, 443) are forwarded
- **`off`** — no network access

Base domains (`nixos.org`) are always included. Plugin domains are merged automatically. Your `network.domains` adds on top of both.

## SSH Identity

Each VM has a stable SSH key pair at `.nixbox/ssh/vm_key{,.pub}`, generated once on first `nixbox up`. The private key is injected into `~/.ssh/id_ed25519` inside the guest. Register the public key on any service the VM needs to reach — it persists across restarts.

## Credentials

Secrets are passed via the `env` attrset. Use `builtins.getEnv` to read from host environment so the file stays safe to commit:

```nix
{
  env = {
    GITHUB_TOKEN = builtins.getEnv "GITHUB_TOKEN";
  };

  scripts = [
    "./scripts/setup-git.sh"
  ];
}
```

All `env` values are sourced from `~/.env` on guest login. Scripts run after boot with env vars available.

## Lifecycle hooks

Run host-side commands at VM lifecycle boundaries. Hooks are `sh -c` strings executed in the project directory. Failures log a warning and continue.

| Event | When |
|---|---|
| `pre-up` | Before VM boot sequence starts |
| `post-up` | After VM is fully ready (SSH works, scripts ran) |
| `pre-down` | Before teardown starts |
| `post-down` | After VM destroyed, network cleaned |

```nix
{
  hooks.post-up = [
    "nixbox aws login"
    "nixbox claude-code sync-config"
  ];
  hooks.pre-down = [
    "echo 'shutting down...'"
  ];
}
```

Plugins can declare hooks too — they merge additively (plugin hooks run first, then user hooks).

## Resources

- **vCPUs** default to all host cores (`nproc`). They're KVM threads scheduled by the host — cheap when idle, no reservation.
- **Memory** defaults to half of host RAM (minimum 4 GB). Uses virtio-balloon with `free_page_reporting` — the configured value is a **limit**, not a reservation. The guest returns unused pages to the host automatically, and the balloon deflates on OOM so the guest can reclaim up to the limit.

## Plugins

Plugins are Nix attrsets that contribute packages, mounts, network domains, env vars, and setup scripts. Stack them in your config — everything merges additively.

### Merge semantics

- **Lists** (packages, mounts, domains, ports, scripts, hooks) — concatenated: base defaults + plugins (in order) + user config. Domains and packages are deduplicated.
- **Attrsets** (env) — shallow merge, user wins on conflict.
- **Scalars** (name, network.mode, resources) — user wins.

### Custom plugins

A plugin is any `.nix` file returning an attrset:

```nix
# my-plugin.nix
{
  nix.packages = [ "rustc" "cargo" ];
  network.domains = [ "crates.io" ];
  scripts = [ ./scripts/setup-rust.sh ];
}
```

Reference by path in your config:

```nix
{
  plugins = [ "claude-code" ./my-plugin.nix ];
}
```

### claude-code

Runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside the VM.

**Provides:** `claude-code` package, `~/.claude` mount, Anthropic/Claude/Sentry domains, tmpfs overlays for virtiofs compatibility.

The `~/.claude` mount shares the host's OAuth session — no `claude /login` needed inside the VM. See [ADR 010](docs/decisions/010-claude-oauth-session.md). The tmpfs overlays work around virtiofs lacking `O_TMPFILE` support (see [ADR 001](docs/decisions/001-virtiofs-sandbox.md)). Add `ANTHROPIC_API_KEY` to `env` if not using OAuth.

**Commands:**

```bash
nixbox claude-code sync-config   # SCP host's ~/.claude.json into the VM
```

**Example config:**

```nix
{
  plugins = [ "claude-code" ];
  name = "dev";
  resources.memoryMB = 16384;
  mounts = [ { source = "."; target = "~/workspace"; } ];
  network.mode = "filtered";
  network.domains = [ "github.com" "githubusercontent.com" "npmjs.org" ];
  env = { GITHUB_TOKEN = builtins.getEnv "GITHUB_TOKEN"; };
  scripts = [ "./scripts/setup-git.sh" ];
}
```

### aws

**Provides:** `awscli2` package, AWS domains, `nixbox aws login` command.

**Commands:**

```bash
nixbox aws login              # Uses $AWS_PROFILE from host
nixbox aws login myprofile    # Explicit profile
```

Authenticates via SSO, injects temporary credentials into the VM, and logs into ECR automatically (registry deduced from account ID and region). Re-run when SSO tokens expire; no VM restart needed.

### scala-sbt

**Provides:** `sbt` + `scala` packages, Maven/SBT resolver domains.

The JDK is specified separately via `nix.packages` so you control the version. Set `MAVEN_REPO_HOST`, `MAVEN_REPO_USER`, and `MAVEN_REPO_PASSWORD` env vars to auto-generate `~/.sbt/1.0/credentials.sbt` for private repositories.

**Example config:**

```nix
{
  plugins = [ "scala-sbt" ];
  name = "dev";
  resources.memoryMB = 16384;
  nix.packages = [ "jdk21" ];
  mounts = [ { source = "."; target = "~/workspace"; } ];
  network.mode = "filtered";
  network.domains = [ "github.com" "nexus.internal.example.com" ];
  env = {
    MAVEN_REPO_HOST = "nexus.internal.example.com";
    MAVEN_REPO_USER = builtins.getEnv "MAVEN_REPO_USER";
    MAVEN_REPO_PASSWORD = builtins.getEnv "MAVEN_REPO_PASSWORD";
  };
}
```

## Known limitations

- **Concurrent VMs** — up to 64 concurrent VMs supported, each with per-VM network isolation via slot-based IP allocation.
- **virtiofs + `O_TMPFILE`** — virtiofs does not support `O_TMPFILE`. Tools that hit this (e.g. Node.js/Claude Code) need tmpfs overlays on affected dirs — the `claude-code` plugin handles this automatically.

### macOS-specific limitations

- **Network filtering** — `filtered` mode is not yet implemented on macOS. Only `open` mode works; `off` and `filtered` will error.
- **Hot-plug mounts** — `nixbox mount` / `nixbox unmount` are not supported. Declare mounts in `config.nix` and restart the VM.
- **Guest IP discovery** — uses ARP scan after boot instead of static assignment. Boot may be slightly slower.

See [ADR 015](docs/decisions/015-macos-vfkit-support.md) for full platform comparison.

## Acknowledgments

- Built on [microvm.nix](https://github.com/microvm-nix/microvm.nix)
- Inspired by [nixcage](https://github.com/hamidr/nixcage)
