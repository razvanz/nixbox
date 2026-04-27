# scala-sbt

Scala toolchain with optional private Maven/Nexus credentials.

## Usage

```nix
{ plugins = [ "scala-sbt" ]; }
```

## What it provides

| Category | Details |
|---|---|
| **Packages** | `sbt`, `scala`, `scala-cli` |
| **Domains** | `maven.org`, `scala-sbt.org`, plus `MAVEN_REPO_HOST` if set |

## Caches

Coursier and ivy2 caches live on the guest's `root.img` at default paths
(`~/.cache/coursier`, `~/.ivy2`). They persist across `up`/`down` for the same
workspace but are **not** shared with the host (see
[ADR-015](../../docs/decisions/015-no-virtiofs-hot-caches.md)). First
`sbt update` per workspace re-downloads dependencies.

## Private repository credentials

Set all three env vars to auto-configure `~/.sbt/1.0/credentials.sbt`:

| Env var | Description |
|---|---|
| `MAVEN_REPO_HOST` | Nexus/Artifactory hostname (e.g. `repo.example.com`) |
| `MAVEN_REPO_USER` | Username |
| `MAVEN_REPO_PASSWORD` | Password or token |

If any are missing, the credentials file is not created.
