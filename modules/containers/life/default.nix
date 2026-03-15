{ ... }:
{
  imports = [
    ./network.nix
    ./storage.nix
    ./actualbudget.nix
    ./ghostfolio
  ];

  users.groups.life = {
    gid = 2200;
  };
}
