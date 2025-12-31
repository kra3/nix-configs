{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.sops
    pkgs.age
  ];

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];
    secrets = {
      root-password.neededForUsers = true;
      kra3-password.neededForUsers = true;
    };
  };
}
