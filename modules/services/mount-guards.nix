{ lib, ... }:
let
  requiredMounts = [
    "/srv/appdata"
    "/srv/databases"
    "/srv/media"
    "/srv/surveillance"
  ];
  guardedServices = [
    "container@media-mgmt"
    "container@media-play"
    "container@monitoring"
    "container@home-auto"
  ];
in
{
  systemd.services = lib.genAttrs guardedServices (_: {
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    serviceConfig.RequiresMountsFor = requiredMounts;
  });
}
