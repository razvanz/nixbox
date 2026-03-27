# Config that uses test plugin + user overrides.
{
  name = "test-plugin";
  plugins = [ ./test-plugin ];
  nix.packages = [ "ripgrep" ];
  network.domains = [ "user.example.com" ];
}
