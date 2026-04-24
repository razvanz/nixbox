# Config that overrides defaults: network mode, extra packages, mounts.
{
  name = "test-overrides";
  network.mode = "filtered";
  network.domains = [ "example.com" ];
  nix.packages = [ "ripgrep" ];
  nix.ldLibraries = [ "libGL" ];
  mounts = [
    { source = "./src"; target = "~/code"; readonly = true; }
  ];
  resources = {
    vcpus = 4;
    memoryMB = 8192;
  };
  env = {
    FOO = "bar";
  };
}
