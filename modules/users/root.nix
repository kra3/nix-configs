{ config, ... }:
{
  sops.secrets."users.root.password".neededForUsers = true;

  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMY4lTahzgn3hOIq3edXBPzg2XdJlcYUBIdWm0BD2HkP sutala root"
    ];
    hashedPasswordFile = config.sops.secrets."users.root.password".path;
  };
}
