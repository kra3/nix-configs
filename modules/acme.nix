{ config, ... }:
{
  sops.secrets."cloudflare.acme.token" = { };

  security.acme = {
    acceptTerms = true;
    defaults = {
      # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      email = "the1.arun@gmail.com";
    };
    certs."karunagath.in" = {
      extraDomainNames = [ "*.karunagath.in" ];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      webroot = null;
      group = "acme";
      credentialFiles = {
        CF_DNS_API_TOKEN_FILE = config.sops.secrets."cloudflare.acme.token".path;
      };
      reloadServices = [ "nginx" "adguardhome" ];
    };
  };
}
