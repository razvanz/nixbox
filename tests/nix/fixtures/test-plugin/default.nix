# Test plugin: adds packages, domains, and a hook.
{
  nix.packages = [ "curl" "jq" ];
  nix.ldLibraries = [ "expat" ];
  network.domains = [ "plugin.example.com" ];
  hooks.post-up = [ "echo plugin-loaded" ];
}
