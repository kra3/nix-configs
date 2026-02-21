{ config, ... }:
{
  sops.secrets."cloudflare.acme.token" = { };

  security.acme = {
    acceptTerms = true;
    defaults = {
      # server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      email = config.vars.acme.email;
    };
    certs.${config.vars.acme.domain} = {
      extraDomainNames = [ "*.${config.vars.acme.domain}" ];
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
