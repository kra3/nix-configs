{
  flake.nixosModules.profiles-media-video-server =
    {
      config,
      flakeModules,
      ...
    }:
    let
      mp = config.vars.network.containers.mediaPlay.localAddress;
      p = config.vars.network.podmanSubnets;
    in
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-play
        flakeModules.nixos.services-media-streaming-iptv
      ];

      # Jellyfin lives in the media-play container; this profile switches it on.
      containers.media-play.config.services.declarative-jellyfin.enable = true;

      networking.firewall.extraForwardRules = ''
        # 8. HA pod → media-play: HA media_player integration (Jellyfin)
        ip saddr ${p.homeAuto} ip daddr ${mp} tcp dport 8096 accept
        # 9. media-mgmt pods → media-play: Seerr authenticates against Jellyfin
        ip saddr ${p.mediaMgmt} ip daddr ${mp} tcp dport 8096 accept
      '';
    };
}
