{
  flake.nixosModules.containers-life-storage =
    { ... }:
    {
      systemd.tmpfiles.rules = [
        "d /srv/appdata/life 2770 root life - -"
        "d /srv/appdata/life/actualbudget 2770 root life - -"
        "d /srv/appdata/life/vaultwarden 0700 root root - -"
      ];
    };
}
