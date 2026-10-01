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
        forwardAuth = true;
        forwardAuthBypass = [
          {
            prefix = "/api/";
            from = "10.3.2.10";
          }
        ];
      };
    };
}
