# Contributing to nixbox

## Development Setup

```bash
# Build the CLI
nix build .#nixbox

# Run from source (no install)
nix run .#nixbox -- <command>

# Install into your profile
nix profile install .#nixbox
```

## Making Changes

1. Fork the repo and create a feature branch from `main`.
2. Make your changes. Keep PRs focused — one logical change per PR.
3. Run the checks before pushing:

```bash
# Lint
nix shell nixpkgs#shellcheck -c shellcheck -x -S warning bin/nixbox lib/functions.bash plugins/*/commands/*.sh plugins/*/scripts/*.sh

# Unit tests
nix shell nixpkgs#bats -c bats tests/unit/

# Nix eval tests
bash tests/run-nix-tests.sh
```

4. Open a PR against `main`. CI runs all three checks automatically.

## Commit Messages

This project uses [conventional commits](https://www.conventionalcommits.org/) to drive automated versioning and releases.

**Format:** `<type>(<scope>): <description>`

| Type | Purpose | Version bump |
|------|---------|-------------|
| `feat` | New feature | minor |
| `fix` | Bug fix | patch |
| `docs` | Documentation only | patch |
| `test` | Adding or updating tests | patch |
| `ci` | CI/workflow changes | patch |
| `chore` | Maintenance, dependencies | patch |
| `refactor` | Code change that neither fixes a bug nor adds a feature | patch |

- Scope is optional but encouraged, e.g. `fix(ssh): ...`
- For breaking changes, add `!` after the type (e.g. `feat!: ...`) or include `BREAKING CHANGE:` in the commit body. This triggers a **major** version bump.

## Code Structure

- `bin/nixbox` — main CLI script
- `lib/functions.bash` — shared pure functions (sourced by CLI and tests)
- `plugins/` — plugin system (`plugins/{name}/default.nix`)
- `docs/decisions/` — architecture decision records (ADRs)
- `tests/unit/` — BATS unit tests
- `tests/nix/` — Nix evaluation tests

New pure/testable logic should go in `lib/functions.bash` with corresponding BATS tests in `tests/unit/`.

## Releases

Releases are fully automated. Every push to `main` triggers the release workflow which:

1. Determines the version bump from conventional commit messages since the last tag.
2. Creates a git tag (e.g. `v0.2.0`).
3. Publishes a GitHub Release with auto-generated notes.

There is no manual release step.
