{
  nix.packages = [ "claude-code" ];

  mounts = [
    {
      source = "~/.claude";
      target = "~/.claude";
    }
  ];

  network.domains = [
    "anthropic.com"
    "claude.com"
    "sentry.io"
  ];

  scripts = [ ./scripts/setup.sh ];
}
