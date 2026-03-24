# 013: Plugins must not inject env vars

**Date:** 2026-03-24
**Status:** accepted

## Problem

Plugins can contribute packages, mounts, network domains, and setup scripts. Should they also be able to inject `env` vars (secrets like `ANTHROPIC_API_KEY`, `AWS_SECRET_ACCESS_KEY`)?

## Decision

No. Plugins must not define `env` entries. All env var passthrough must be explicitly declared in the user's `.nixbox/config.nix`.

## Rationale

Env vars are the primary mechanism for passing secrets into the guest. A plugin that silently injects `ANTHROPIC_API_KEY = builtins.getEnv "ANTHROPIC_API_KEY"` means the user may not realize a host secret is being forwarded into the VM — especially if they're stacking multiple plugins. This violates nixbox's "explicit" principle: secrets passed via `env`, mounts opted-in, write access deliberate.

Packages, domains, and scripts are visible in their effects (installed binaries, resolved DNS, boot output). Env vars are invisible — they silently appear in `~/.env` inside the guest. The cost of requiring users to add one line to their config is low; the cost of a secret leaking into a VM the user didn't expect is high.

## Consequences

- Every secret must appear in the user's config, making the security posture auditable from a single file.
- Plugins that need env vars must document which ones to add. This is a feature, not a limitation — it forces users to opt in.
- The `env` field in `resolve.nix` still merges from all layers. This decision is a convention enforced by plugin authors, not by code. A future lint in `nixbox doctor` could warn if a plugin contributes `env` entries.
