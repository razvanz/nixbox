# 012: Per-workspace `.nixbox/` directory

**Date:** 2026-03-24
**Status:** accepted

## Problem

Config lived in `nixbox.nix` at the workspace root while all runtime state (SSH keys, build artifacts, images, PID files) lived in `~/.nixbox/`. This split project state across two locations:

- SSH keys in `~/.nixbox/ssh/` were shared across all workspaces — a key regeneration in one workspace broke builds in others.
- Build artifacts and VM images in `~/.nixbox/run/<name>/` were keyed by project name, not path. Two workspaces with the same directory name would collide.
- State directories under `~/.nixbox/state/<name>/` had the same collision problem.
- Users had to mentally map between "config is here, state is over there."

## Decision

Move to a per-workspace `.nixbox/` directory that contains everything: config, SSH keys, build artifacts, and runtime state. The single-VM enforcement pointer (`nixbox-active`) lives in `$XDG_RUNTIME_DIR` — volatile by design, cleared on reboot.

```
$WORKSPACE/.nixbox/
├── config.nix          # user config (was nixbox.nix)
├── .gitignore          # ignores everything except config.nix and .gitignore
├── ssh/                # per-workspace SSH keypair
├── build/              # nix build staging
├── runner -> /nix/store/…
├── run/                # VM runtime (root.img, sockets, logs)
├── state/              # lifecycle (pid, name, start_time, mount tracking)
└── tmp/                # ephemeral (env disk staging)

$XDG_RUNTIME_DIR/nixbox-active   # path to NIXBOX_DIR of running VM
```

`nixbox init` creates `.nixbox/` with `config.nix` and a `.gitignore` that ignores everything except those two files. The `find_nixbox_dir()` function walks up from `$PWD` looking for `.nixbox/config.nix`, replacing the old `find_config()` that looked for `nixbox.nix`.

The project name for `resolve.nix` now uses `dirOf (dirOf configPath)` to skip the `.nixbox/` level and get the workspace directory name.

## Consequences

- **Self-contained workspaces** — cloning a repo and running `nixbox up` produces all state locally. No implicit dependency on `~/.nixbox/` contents from a prior session.
- **No name collisions** — paths are workspace-absolute, not name-keyed. Two workspaces named `dev/` coexist without interference.
- **Per-workspace SSH keys** — each workspace generates its own keypair on first `up`. A rebuild in one workspace cannot invalidate another's key.
- **Clean gitignore** — `.nixbox/.gitignore` keeps generated files out of version control while committing `config.nix`. No repo-root `.gitignore` entries needed.
- **No global state** — the `active` pointer lives in `$XDG_RUNTIME_DIR`, volatile and cleared on reboot. No `~/.nixbox/` directory exists. No orphaned state accumulates across deleted workspaces.
- **Migration** — existing setups with `nixbox.nix` and `~/.nixbox/` state need manual migration: move config to `.nixbox/config.nix`, delete `~/.nixbox/`, and re-run `nixbox up` to regenerate keys and rebuild.
