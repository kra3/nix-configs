{
  flake.nixosModules.services-system-vim = { pkgs, ... }: {
    environment.systemPackages = [
      pkgs.vim
    ];
  };
}
