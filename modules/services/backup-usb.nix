{
  flake.nixosModules.services-backup-usb =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      disk = "/dev/disk/by-id/usb-WD_My_Passport_0827_575836314137354531543237-0:0-part1";
      diskUnit = "dev-disk-by\\x2did-usb\\x2dWD_My_Passport_0827_575836314137354531543237\\x2d0:0\\x2dpart1.device";

      # source dataset -> template; the target is backup/<last path component>
      sources = {
        "rpool/appdata" = "app";
        "rpool/databases" = "app";
        "tank/data/music" = "library";
        "tank/data/books" = "library";
        "tank/data/audiobooks" = "library";
        "tank/data/reference" = "library";
        "tank/personal" = "personal";
      };

      keep = {
        frequently = 0;
        hourly = 0;
        daily = 0;
        weekly = 0;
        monthly = 0;
        yearly = 0;
      };

      targetConf = pkgs.writeTextDir "sanoid.conf" (
        lib.generators.toINI { } (
          {
            template_default = keep // {
              daily = 30;
              monthly = 12;
            };
            template_personal = keep // {
              daily = 30;
              monthly = 24;
            };
          }
          // lib.mapAttrs' (
            src: tpl:
            lib.nameValuePair "backup/${baseNameOf src}" {
              use_template = if tpl == "personal" then "personal" else "default";
              autosnap = "no";
              autoprune = "yes";
            }
          ) sources
        )
      );
    in
    {
      services.sanoid = {
        enable = true;
        templates = {
          app = keep // {
            hourly = 48;
            daily = 14;
            monthly = 3;
          };
          library = keep // {
            daily = 14;
            monthly = 6;
          };
          personal = keep // {
            daily = 7;
            monthly = 12;
          };
          surveillance = keep // {
            daily = 7;
            weekly = 4;
          };
        };
        datasets = lib.mapAttrs (_: tpl: { useTemplate = [ tpl ]; }) sources // {
          "tank/surveillance".useTemplate = [ "surveillance" ];
        };
      };

      systemd.services.backup-usb = {
        description = "Replicate ZFS datasets to the USB backup pool";
        after = [
          "zfs.target"
          diskUnit
        ];
        wantedBy = [ diskUnit ];
        startAt = "*-*-* 03:30";
        path = [
          pkgs.sanoid
          config.boot.zfs.package
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "backup-usb";
          CacheDirectory = "backup-usb";
          RuntimeDirectory = "backup-usb";
          TimeoutStartSec = "12h";
        };
        script = ''
          set -euo pipefail
          last=/var/lib/backup-usb/last-ok
          [ -e "$last" ] || touch "$last"

          if [ ! -e ${lib.escapeShellArg disk} ]; then
            age=$(( ($(date +%s) - $(stat -c %Y "$last")) / 86400 ))
            echo "backup-usb: disk not connected, last successful backup $age days ago"
            [ "$age" -lt 7 ] || exit 1
            exit 0
          fi

          imported=0
          trap 'if [ "$imported" = 1 ]; then zpool export backup || true; fi' EXIT
          if ! zpool list backup >/dev/null 2>&1; then
            zpool import -N -d /dev/disk/by-id backup
            imported=1
          fi
          [ "$(zfs get -H -o value keystatus backup)" = available ] || zfs load-key backup

          failed=0
          for src in ${lib.escapeShellArgs (lib.attrNames sources)}; do
            syncoid --no-sync-snap --include-snaps='^autosnap_.*_(daily|monthly)$' \
              "$src" "backup/''${src##*/}" || { echo "backup-usb: $src failed"; failed=1; }
          done
          sanoid --configdir=${targetConf} --cache-dir=/var/cache/backup-usb \
            --run-dir=/run/backup-usb --force-update --prune-snapshots

          scrubbed=/var/lib/backup-usb/last-scrub
          if [ ! -e "$scrubbed" ] || [ -n "$(find "$scrubbed" -mtime +30)" ]; then
            zpool scrub -w backup
            touch "$scrubbed"
          fi
          zpool status -x backup | grep -q 'is healthy' || { zpool status backup; exit 1; }

          if [ "$imported" = 1 ]; then
            zpool export backup
            imported=0
          fi
          [ "$failed" = 0 ] || exit 1
          touch "$last"
          echo "backup-usb: OK"
        '';
      };
      systemd.timers.backup-usb.timerConfig.Persistent = true;
    };
}
