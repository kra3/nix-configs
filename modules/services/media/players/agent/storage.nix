{
  users.groups.media = {
    gid = 2000;
  };

  systemd.tmpfiles.rules = [
    "d /srv/appdata/media-play 0770 root media - -"
    "d /srv/appdata/media-play/jellyfin 0770 root media - -"
  ];
}
