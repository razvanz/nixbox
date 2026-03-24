# .nixbox/config.nix — microVM sandbox config
# Created by 'nixbox init'.
{
  # # --- Plugins ---
  # # Built-in: "claude-code", "aws", "scala-sbt"
  # # Or use a path for custom plugins: ./my-plugin.nix
  # plugins = [ "claude-code" "aws" ];

  # name = "myproject"; # Default: directory basename

  # # --- Resources ---
  # resources.vcpus = 8; # Default: all host cores (no rebuild)
  # resources.memoryMB = 16384; # Default: half of host RAM (min 4GB); balloon returns unused pages (no rebuild)

  # # --- Mounts ---
  # mounts = [
  #   {
  #     source = ".";
  #     target = "~/workspace";
  #   }
  #   {
  #     source = "../shared";
  #     target = "/shared";
  #     readonly = true;
  #   }
  # ];

  # # --- Networking ---
  # network.mode = "open"; # "off" | "filtered" | "open"
  # # Additive — base defaults (nixos.org) and plugin domains are always included.
  # # Entries are suffix-matched: "github.com" covers api.github.com, etc.
  # network.domains = [
  #   "github.com"
  # ];
  # network.ports = [ 80 443 ];

  # # --- Nix packages ---
  # # Added on top of base (git, openssh, jq, curl) and plugin packages. Triggers auto-rebuild on next `up`.
  # nix.packages = [
  #   "nodejs_22"
  # ];

  # # --- Setup scripts ---
  # # Ran inside guest after boot (after plugin scripts), with env vars sourced.
  # scripts = [
  #   "./scripts/setup-git.sh"
  # ];

  # # --- Environment passthrough ---
  # env = {
  #   GITHUB_TOKEN = builtins.getEnv "GITHUB_TOKEN";
  # };

  # # --- Lifecycle hooks ---
  # # Commands run on the host at lifecycle boundaries. Failures warn but don't abort.
  # hooks.post-up = [
  #   "nixbox aws login"
  # ];
  # hooks.pre-down = [
  #   "echo 'shutting down...'"
  # ];
}
