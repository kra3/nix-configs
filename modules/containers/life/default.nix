{ ... }:
{
  imports = [
    ./network.nix
    ./storage.nix
    # ./firefly.nix   # enable when deploying firefly
    ./actualbudget.nix
    ./ghostfolio.nix
  ];
}
