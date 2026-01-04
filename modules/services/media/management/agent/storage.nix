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
    "d /srv/media/downloads/usenet/complete/tv 0775 root media - -"
    "d /srv/media/downloads/usenet/complete/movies 0775 root media - -"
    "d /srv/media/downloads/usenet/complete/music 0775 root media - -"
    "d /srv/media/downloads/usenet/complete/books 0775 root media - -"
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
    "d /srv/appdata/media-mgmt 0770 root media - -"
    "d /srv/appdata/media-mgmt/radarr 0770 root media - -"
    "d /srv/appdata/media-mgmt/sonarr 0770 root media - -"
    "d /srv/appdata/media-mgmt/prowlarr 0770 root media - -"
    "d /srv/appdata/media-mgmt/sabnzbd 0770 root media - -"
    "d /srv/appdata/media-mgmt/bazarr 0770 root media - -"
    "d /srv/appdata/media-mgmt/recyclarr 0770 root media - -"
    "d /srv/appdata/media-mgmt/lidarr 0770 root media - -"
    "d /srv/appdata/media-mgmt/jellyseerr 0770 root media - -"
  ];
}
