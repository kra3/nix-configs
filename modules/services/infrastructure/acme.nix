{
  flake.nixosModules.services-infrastructure-acme =
    { config, ... }:
    {
      sops.secrets."cloudflare.acme.token" = {
        owner = "acme";
        group = "acme";
      };

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
          # Local unbound has karunagath.in. as a redirect zone which swallows SOA
          # queries — lego can't find the zone boundary and fails with
          # "failed to find zone in.". Force lego to use public resolvers directly.
          dnsResolver = "1.1.1.1:53";
          reloadServices = [
            "nginx"
            "adguardhome"
          ];
        };
      };
    };
}
