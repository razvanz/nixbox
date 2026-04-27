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
| **Commands** | `nixbox scala-sbt warm-cache` |

## Caches

Coursier and ivy2 caches live on the guest's `root.img` at default paths
(`~/.cache/coursier`, `~/.ivy2`). On `nixbox up` the plugin's `post-up`
hook runs `nixbox scala-sbt warm-cache`, which streams the host's
`~/.cache/coursier` and `~/.ivy2` over the SSH channel into the guest
(idempotent — guarded by a sentinel inside each cache dir). Subsequent
boots are no-ops. Runtime sbt I/O lives entirely on `root.img` and never
crosses virtiofs (see
[ADR-015](../../docs/decisions/015-no-virtiofs-hot-caches.md)).

If the host paths don't exist, the warmup is skipped and the cache is
populated by `sbt update` over the network. You can also re-run the
command manually (`nixbox scala-sbt warm-cache`) to refresh after
removing the sentinel files.

## Private repository credentials

Set all three env vars to auto-configure `~/.sbt/1.0/credentials.sbt`:

| Env var | Description |
|---|---|
| `MAVEN_REPO_HOST` | Nexus/Artifactory hostname (e.g. `repo.example.com`) |
| `MAVEN_REPO_USER` | Username |
| `MAVEN_REPO_PASSWORD` | Password or token |

If any are missing, the credentials file is not created.
