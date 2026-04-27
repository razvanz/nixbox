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
}
