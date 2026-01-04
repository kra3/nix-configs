{
  users.groups.media = {
    gid = 2000;
  };

  services.lidarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 8686;
      };
    };
    environmentFiles = [ "/run/secrets/media.lidarr.env" ];
  };

  users.users.lidarr.extraGroups = [ "media" ];

  systemd.services.lidarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
