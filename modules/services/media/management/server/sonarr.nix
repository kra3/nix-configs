{
  users.groups.media = {
    gid = 2000;
  };

  services.sonarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 8989;
      };
    };
    environmentFiles = [ "/run/secrets/media.sonarr.env" ];
  };

  users.users.sonarr.extraGroups = [ "media" ];

  systemd.services.sonarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
