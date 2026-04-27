{
  nix.packages = [
    "sbt"
    "scala"
    "scala-cli"
  ];

  network.domains =
    [
      "maven.org"
      "scala-sbt.org"
    ]
    ++ (
      let host = builtins.getEnv "MAVEN_REPO_HOST";
      in if host != "" then [ host ] else [ ]
    );

  scripts = [ ./scripts/setup.sh ];

  # Warm coursier/ivy2 caches from host on every up. The command is
  # sentinel-guarded inside the guest, so re-runs are no-ops once warmed.
  hooks.post-up = [ "nixbox scala-sbt warm-cache" ];
}
