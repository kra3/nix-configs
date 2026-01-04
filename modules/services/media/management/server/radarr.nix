{
  users.groups.media = {
    gid = 2000;
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 7878;
      };
    };
    environmentFiles = [ "/run/secrets/media.radarr.env" ];
  };

  users.users.radarr.extraGroups = [ "media" ];

  systemd.services.radarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
