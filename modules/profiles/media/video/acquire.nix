{
  flake.nixosModules.profiles-media-video-acquire =
    {
      config,
      lib,
      flakeModules,
      ...
    }:
    let
      jellyfin = config.containers.media-play.config.services.declarative-jellyfin.enable or false;
    in
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-radarr
        flakeModules.nixos.containers-media-mgmt-sonarr
        flakeModules.nixos.containers-media-mgmt-recyclarr
        flakeModules.nixos.containers-media-mgmt-maintainerr
        flakeModules.nixos.containers-media-mgmt-seerr
      ];

      networking.firewall.extraForwardRules = ''
        # 9a. media-play → Seerr: Jellyfin plugins (Home Screen Sections, Litefin) call its API
        ${lib.optionalString jellyfin "ip saddr ${config.vars.network.containers.mediaPlay.localAddress} ip daddr ${config.vars.network.podmanAddresses.seerr} tcp dport 5055 accept"}
      '';
    };
}
