{ lib, ... }:
let
  requiredMounts = [
    "/srv/appdata"
    "/srv/databases"
    "/srv/media"
  ];
  guardedServices = [
    "container@media-mgmt"
    "container@media-play"
    "container@monitoring"
  ];
in
{
  systemd.services = lib.genAttrs guardedServices (_: {
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    serviceConfig.RequiresMountsFor = requiredMounts;
  });
}
