# scala-sbt

Scala toolchain with optional private Maven/Nexus credentials.

## Usage

```nix
{ plugins = [ "scala-sbt" ]; }
```

## What it provides

| Category | Details |
|---|---|
| **Packages** | `sbt`, `scala`, `scala-cli`, `rsync` |
| **Domains** | `maven.org`, `scala-sbt.org`, plus `MAVEN_REPO_HOST` if set |

## Caches

Coursier and ivy2 caches live on the guest's `root.img` at default paths
(`~/.cache/coursier`, `~/.ivy2`). On first boot per workspace, the plugin
warms them by `rsync`-copying from the host's `~/.cache/coursier` and
`~/.ivy2` (mounted read-only at `/mnt/host-cache/...` for the boot, then
idle). Subsequent boots skip the warmup; sbt's runtime I/O lives entirely
on `root.img` and never crosses virtiofs.

If the host paths don't exist, the warmup is skipped and the cache is
populated by `sbt update` over the network. See
[ADR-015](../../docs/decisions/015-no-virtiofs-hot-caches.md) for the
rationale.

## Private repository credentials

Set all three env vars to auto-configure `~/.sbt/1.0/credentials.sbt`:

| Env var | Description |
|---|---|
| `MAVEN_REPO_HOST` | Nexus/Artifactory hostname (e.g. `repo.example.com`) |
| `MAVEN_REPO_USER` | Username |
| `MAVEN_REPO_PASSWORD` | Password or token |

If any are missing, the credentials file is not created.
