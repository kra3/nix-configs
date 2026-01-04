{
  users.groups.media = {
    gid = 2000;
  };

  systemd.tmpfiles.rules = [
    "d /srv/media 0775 root media - -"
    "d /srv/media/downloads 0775 root media - -"
    "d /srv/media/downloads/usenet 0775 root media - -"
    "d /srv/media/downloads/usenet/incomplete 0775 root media - -"
    "d /srv/media/downloads/usenet/complete 0775 root media - -"
    "d /srv/media/downloads/torrent 0775 root media - -"
    "d /srv/media/downloads/torrent/incomplete 0775 root media - -"
    "d /srv/media/downloads/torrent/complete 0775 root media - -"
    "d /srv/media/library 0775 root media - -"
    "d /srv/media/library/movies 0775 root media - -"
    "d /srv/media/library/tv 0775 root media - -"
    "d /srv/media/library/songs 0775 root media - -"
    "d /srv/media/library/books 0775 root media - -"
    "d /srv/media/library/anime 0775 root media - -"
    "d /srv/media/library/audiobooks 0775 root media - -"
    "d /srv/appdata 0770 root media - -"
    "d /srv/appdata/media-management 0770 root media - -"
    "d /srv/appdata/media-management/radarr 0770 root media - -"
    "d /srv/appdata/media-management/sonarr 0770 root media - -"
    "d /srv/appdata/media-management/prowlarr 0770 root media - -"
    "d /srv/appdata/media-management/sabnzbd 0770 root media - -"
    "d /srv/appdata/media-management/bazarr 0770 root media - -"
    "d /srv/appdata/media-management/recyclarr 0770 root media - -"
    "d /srv/appdata/media-management/lidarr 0770 root media - -"
    "d /srv/appdata/media-management/jellyseerr 0770 root media - -"
  ];
}
