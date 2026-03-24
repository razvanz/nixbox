# scala-sbt

Scala toolchain with optional private Maven/Nexus credentials.

## Usage

```nix
{ plugins = [ "scala-sbt" ]; }
```

## What it provides

| Category | Details |
|---|---|
| **Packages** | `sbt`, `scala` |
| **Mounts** | `~/.cache/coursier`, `~/.ivy2` (only if they exist on host) |
| **Domains** | `maven.org`, `scala-sbt.org`, plus `MAVEN_REPO_HOST` if set |

## Private repository credentials

Set all three env vars to auto-configure `~/.sbt/1.0/credentials.sbt`:

| Env var | Description |
|---|---|
| `MAVEN_REPO_HOST` | Nexus/Artifactory hostname (e.g. `repo.example.com`) |
| `MAVEN_REPO_USER` | Username |
| `MAVEN_REPO_PASSWORD` | Password or token |

If any are missing, the credentials file is not created.
