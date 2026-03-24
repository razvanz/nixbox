{
  nix.packages = [ "awscli2" ];

  network.domains = [
    "amazonaws.com"
    "aws.amazon.com"
  ];
}
