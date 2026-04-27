let
  home = builtins.getEnv "HOME";
  # Bootstrap mount: RO virtiofs share read once at boot by setup.sh, then
  # idle for the rest of the VM's lifetime (see ADR-015). Skipped if the
  # host path doesn't exist.
  warmFromHost = src: target:
    if home != "" && builtins.pathExists (home + src)
    then [ { source = "~" + src; inherit target; readonly = true; } ]
    else [ ];
in
{
  nix.packages = [
    "sbt"
    "scala"
    "scala-cli"
    "rsync"
  ];

  mounts =
    warmFromHost "/.cache/coursier" "/mnt/host-cache/coursier"
    ++ warmFromHost "/.ivy2" "/mnt/host-cache/ivy2";

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

  # Release bootstrap mounts after warmup (ADR-015): drops the guest mount,
  # detaches the virtio device, kills virtiofsd → frees its accumulated FDs.
  hooks.post-up = [
    "nixbox unmount /mnt/host-cache/coursier"
    "nixbox unmount /mnt/host-cache/ivy2"
  ];
}
