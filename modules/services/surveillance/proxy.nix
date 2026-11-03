{
  flake.nixosModules.services-surveillance-proxy =
    {
      config,
      lib,
      flakeLib,
      ...
    }:
    let
      homeAutoIp = config.containers.home-auto.localAddress or "10.0.50.8";
    in
    {
      services.nginx.virtualHosts."z2m.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${homeAutoIp}:8080";
        forwardAuth = true;
      };

      services.nginx.virtualHosts."nvr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${homeAutoIp}:80";
        # Remote-* headers come only from the Authelia auth_request result (never the client's).
        forwardAuth = true;
        # Home Assistant (10.3.2.10) is bypassed in Authelia and has no session, so
        # Authelia returns no Remote-User; give it a fixed identity for Frigate's proxy-auth.
        locationExtraConfig = ''
          if ($user = "") { set $user "homeassistant"; }
        '';
      };
    };
}
