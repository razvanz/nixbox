# 011: Guest setup via user-provided scripts

**Date:** 2026-03-24
**Status:** accepted

## Problem

The VM needs tool-specific configuration after boot: git identity, SBT credentials, private registry auth, language-specific tooling installs (`npm install -g`), etc. Two approaches:

1. **Declarative modules** — nixbox interprets structured config fields (`git.name`, `sbt.credentials`, ...) and generates the appropriate files/commands
2. **User scripts** — nixbox runs arbitrary shell scripts provided by the user

## Decision

User scripts. The `scripts` field in `.nixbox/config.nix` lists paths to shell scripts that run inside the guest after boot, with env vars from `env` already sourced:

```nix
{
  env = {
    NEXUS_USER = builtins.getEnv "MAVEN_REPO_USER";
  };
  scripts = [ "./scripts/setup.sh" ];
}
```

Scripts are SCP'd into the guest and executed as the VM user. Relative paths resolve against the workspace root (parent of `.nixbox/`).

## Alternatives considered

**Declarative modules** (e.g. `git.name`, `sbt.credentials`): Would require nixbox to model every tool's config format. Each new tool means new code in nixbox. Breaks when tools change their config layout. Attractive for common cases but creates an ever-growing surface area.

**Nix-level config generation** (e.g. NixOS `programs.git`): Would require rebuilding the VM image for config changes. The current architecture separates image-time concerns (packages) from boot-time concerns (credentials, tool config) deliberately — scripts keep boot-time setup fast and rebuildless.

**cloud-init**: Standard in cloud VMs for user-data injection, but adds unnecessary weight here. cloud-init pulls in Python, systemd units, and a multi-stage boot pipeline (network → config → final) designed for cloud metadata services we don't have. It also expects a data source (IMDS, NoCloud ISO, etc.) — we'd need to generate a NoCloud disk image just to pass a shell script. The SCP+SSH approach does the same thing with zero guest-side dependencies and no image rebuild, using an SSH connection that already exists for `nixbox shell`.

**Ignition** (Fedora CoreOS, Flatcar): The closest local-VM equivalent to cloud-init — JSON config on a small partition, no metadata service needed. But it's tightly coupled to CoreOS/Flatcar (nixbox runs NixOS), runs at initrd/first-boot time (nixbox scripts need mounts and env vars ready post-boot), and is one-shot by design (nixbox scripts run every `up`). Would mean layering a second provisioning system on top of NixOS + microvm.nix for no gain.

## Consequences

- **Decoupled from toolchains** — nixbox has zero knowledge of git, SBT, npm, Docker, or any other tool. Users compose their own setup using the same primitives they'd use in a Dockerfile or CI script.
- **No abstraction tax** — users don't need to learn a nixbox-specific DSL for tool config. Shell scripts are universally understood and directly testable.
- **No validation** — nixbox doesn't check that scripts exist at config eval time (only at boot). A typo in a script path fails late. Acceptable since `nixbox doctor` catches this before boot.
- **Ordering is sequential** — scripts run in array order after all mounts are ready and env vars are sourced. Users control dependencies by ordering entries.
- **Rerun cost** — scripts run on every `nixbox up`, not just first boot. Scripts must be idempotent or guard against re-execution themselves.
