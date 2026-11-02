{ config, ... }:
{
  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-KINGSTON_SFYRDK2000G_50026B728330F14D";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };

      hdd = {
        type = "disk";
        device = "/dev/disk/by-id/ata-HUA723030ALA640_YXG86P1A";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          mountpoint = "none";
          compression = "zstd";
          atime = "off";
          relatime = "on";
          xattr = "sa";
        };

        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              acltype = "posix";
            };
          };
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
          };
          appdata = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/appdata";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
            };
          };
          databases = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/databases";
              recordsize = "16K";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
              primarycache = "all";
              logbias = "throughput";
            };
          };
        };
      };

      tank = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          mountpoint = "none";
          recordsize = "1M";
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          primarycache = "metadata";
          secondarycache = "none";
          relatime = "on";
        };
        datasets = {
          data = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/media";
              logbias = "throughput";
            };
          };
          "data/music" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/media/library/music";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
            };
          };
          "data/books" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/media/library/books";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
            };
          };
          "data/audiobooks" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/media/library/audiobooks";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
            };
          };
          "data/reference" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/media/library/reference";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
            };
          };
          personal = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/personal";
              compression = "zstd";
              atime = "off";
              xattr = "sa";
            };
          };
          surveillance = {
            type = "zfs_fs";
            options = {
              mountpoint = "/srv/surveillance";
              logbias = "throughput";
            };
          };
        };
      };
    };
  };
}
