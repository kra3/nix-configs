{ config, pkgs, ... }:
{
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    gnupg.sshKeyPaths = [ ];
    secrets = {
      "users.root.password".neededForUsers = true;
      "users.kra3.password".neededForUsers = true;
      "cloudflare.dns_api_token" = { };
    };
  };
}
