{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /srv/appdata/life 2770 root media - -"
    "d /srv/appdata/life/firefly 2770 root media - -"
    "d /srv/appdata/life/firefly/upload 0777 root root - -"
    "d /srv/appdata/life/actualbudget 2770 root media - -"
    "d /srv/appdata/life/ghostfolio 2770 root media - -"
  ];
}
