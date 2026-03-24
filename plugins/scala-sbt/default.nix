let
  home = builtins.getEnv "HOME";
  mountIf = path: target:
    if home != "" && builtins.pathExists (home + path)
    then [ { source = "~" + path; inherit target; } ]
    else [ ];
in
{
  nix.packages = [
    "sbt"
    "scala"
  ];

  mounts =
    mountIf "/.cache/coursier" "~/.cache/coursier"
    ++ mountIf "/.ivy2" "~/.ivy2";

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
