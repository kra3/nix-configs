{
  flake.nixosModules.profiles-observability-server =
    {
      config,
      lib,
      flakeModules,
      ...
    }:
    let
      c = config.vars.network.containers;
      p = config.vars.network.podmanSubnets;
      mon = c.monitoring.localAddress;
      mp = c.mediaPlay.localAddress;
      ha = c.homeAuto.localAddress;
      haNet = p.homeAuto;
      jellyfin = config.containers.media-play.config.services.declarative-jellyfin.enable or false;
      unpackerr = config.virtualisation.quadlet.containers ? unpackerr;
    in
    {
      imports = [
        flakeModules.nixos.containers-monitoring
        # Grafana's "Home Assistant" datasource reads the hass db as grafana_ro.
        flakeModules.nixos.services-postgres
      ];

      networking.firewall.extraForwardRules = ''
        # 1. monitoring → media-play: scrape node-exporter + navidrome + jellyfin metrics
        ip saddr ${mon} ip daddr ${mp} tcp dport { 9100, 4533${lib.optionalString jellyfin ", 8096"} } accept
        # 1a. monitoring → media-mgmt: scrape slskd (+ unpackerr) metrics
        ${lib.optionalString unpackerr "ip saddr ${mon} ip daddr ${config.vars.network.podmanAddresses.unpackerr} tcp dport 5656 accept"}
        ip saddr ${mon} ip daddr ${config.vars.network.podmanAddresses.slskd} tcp dport 5030 accept
        # 2. monitoring → home-auto: scrape node-exporter + frigate metrics
        ip saddr ${mon} ip daddr ${ha} tcp dport { 9100, 80 } accept
        # 3. monitoring → HA pod: scrape Home Assistant Prometheus endpoint
        ip saddr ${mon} ip daddr ${haNet} tcp dport 8123 accept
        # 4. home-auto → monitoring: ship logs via Alloy → Loki
        ip saddr ${ha} ip daddr ${mon} tcp dport 3100 accept
        # 5. media-play → monitoring: ship logs via Alloy → Loki
        ip saddr ${mp} ip daddr ${mon} tcp dport 3100 accept
      '';
    };
}
