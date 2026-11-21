{
  flake.nixosModules.containers-life-storage =
    { ... }:
    {
      systemd.tmpfiles.rules = [
        "d /srv/appdata/life 2770 root life - -"
        "d /srv/appdata/life/actualbudget 2770 2402 life - -"
        "Z /srv/appdata/life/actualbudget - 2402 life - -"
        "d /srv/appdata/life/vaultwarden 0700 2401 2401 - -"
        "Z /srv/appdata/life/vaultwarden - 2401 2401 - -"
      ];
    };
}
