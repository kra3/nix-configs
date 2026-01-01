{ config, ... }:
{
  users.users.nginx.extraGroups = [ "acme" ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      email = "the1.arun@gmail.com";
    };
    certs."karunagath.in" = {
      extraDomainNames = [ "*.karunagath.in" ];
      dnsProvider = "cloudflare";
      credentialFiles = {
        CF_DNS_API_TOKEN_FILE = config.sops.secrets."cloudflare.dns_api_token".path;
      };
      reloadServices = [ "nginx" ];
    };
  };
}
