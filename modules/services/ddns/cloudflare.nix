{ config, ... }:
{
  sops.secrets."cloudflare.ddns.token" = { };

  services.cloudflare-ddns = {
    enable = true;
    credentialsFile = config.sops.secrets."cloudflare.ddns.token".path;
    domains = [ "*.karunagath.in" ];
    provider.ipv6 = "none";
  };
}
