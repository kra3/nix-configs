{ lib, ... }:
{
  flake.lib.nginx = {
    # CIDR allowlist block for nginx: allow the given CIDRs, deny everything else.
    mkAllowBlock = cidrs: ''
      ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") cidrs)}
      deny all;
    '';

    # Standard "TLS-terminated reverse proxy to a single upstream" vhost shape
    # shared by most self-hosted apps here (ACME cert, forced SSL, CIDR allowlist,
    # one proxied location).
    mkProxyVhost =
      {
        domain,
        cidrs,
        upstream,
        websockets ? true,
        vhostExtraConfig ? "",
        locationExtraConfig ? null,
      }:
      {
        useACMEHost = domain;
        forceSSL = true;
        extraConfig = ''
          ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") cidrs)}
          deny all;
          ${vhostExtraConfig}
        '';
        locations."/" = {
          proxyPass = upstream;
          proxyWebsockets = websockets;
        }
        // lib.optionalAttrs (locationExtraConfig != null) {
          extraConfig = locationExtraConfig;
        };
      };
  };
}
