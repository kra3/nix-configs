{ lib, ... }:
let
  # Forward-auth snippet for apps with no OIDC support of their own: nginx
  # asks Authelia (reachable directly at 127.0.0.1, no container hairpin
  # involved) whether the request's session cookie is authenticated before
  # proxying through. Endpoint/headers per Authelia's documented nginx
  # auth_request integration (server.endpoints.authz."auth-request" ships
  # as one of Authelia's built-in defaults, no extra Authelia config needed).
  forwardAuthLocationConfig = ''
    auth_request /internal/authelia/authz;
    auth_request_set $user $upstream_http_remote_user;
    auth_request_set $groups $upstream_http_remote_groups;
    auth_request_set $name $upstream_http_remote_name;
    auth_request_set $email $upstream_http_remote_email;
    proxy_set_header Remote-User $user;
    proxy_set_header Remote-Groups $groups;
    proxy_set_header Remote-Email $email;
    proxy_set_header Remote-Name $name;
    auth_request_set $redirection_url $upstream_http_location;
    error_page 401 =302 $redirection_url;
  '';
in
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
        forwardAuth ? false,
      }:
      {
        useACMEHost = domain;
        forceSSL = true;
        extraConfig = ''
          ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") cidrs)}
          deny all;
          ${vhostExtraConfig}
        '';
        locations = {
          "/" = {
            proxyPass = upstream;
            proxyWebsockets = websockets;
          }
          // lib.optionalAttrs (forwardAuth || locationExtraConfig != null) {
            extraConfig = lib.concatStringsSep "\n" (
              lib.optional forwardAuth forwardAuthLocationConfig
              ++ lib.optional (locationExtraConfig != null) locationExtraConfig
            );
          };
        }
        // lib.optionalAttrs forwardAuth {
          "/internal/authelia/authz" = {
            extraConfig = ''
              internal;
              proxy_pass http://127.0.0.1:9091/api/authz/auth-request;
              proxy_set_header X-Original-Method $request_method;
              proxy_set_header X-Original-URL $scheme://$host$request_uri;
              proxy_set_header X-Forwarded-For $remote_addr;
              proxy_set_header Content-Length "";
              proxy_set_header Connection "";
              proxy_pass_request_body off;
              proxy_http_version 1.1;
            '';
          };
        };
      };
  };
}
