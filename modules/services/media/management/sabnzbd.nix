{ config, lib, pkgs, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.sabnzbd = {
    enable = true;
    configFile = "/var/lib/sabnzbd/sabnzbd.ini";
    openFirewall = true;
  };

  users.users.sabnzbd = {
    group = lib.mkForce "media";
    extraGroups = [ "media" ];
  };

  systemd.services.sabnzbd = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    preStart = ''
      cfg="${config.services.sabnzbd.configFile}"
      if [ ! -f "$cfg" ]; then
        ${pkgs.coreutils}/bin/install -m 0640 -D /dev/null "$cfg"
      fi

      ${pkgs.gnused}/bin/sed -i '/^host_whitelist[[:space:]]*=.*/d' "$cfg"
      ${pkgs.gnused}/bin/sed -i '/^host_whitelist_enabled[[:space:]]*=.*/d' "$cfg"
      ${pkgs.gnused}/bin/sed -i '/^permissions[[:space:]]*=.*/d' "$cfg"
      ${pkgs.gnused}/bin/sed -i '/^umask[[:space:]]*=.*/d' "$cfg"
      whitelist="sabnzbd.karunagath.in,10.0.50.4,127.0.0.1,localhost"
      ${pkgs.gawk}/bin/awk -v wl="$whitelist" '
        BEGIN { in_misc=0; done=0 }
        /^\[misc\]$/ { print; in_misc=1; next }
        in_misc && /^\[/ {
          if (!done) {
            print "host_whitelist_enabled = 1"
            print "host_whitelist = " wl
            print "permissions = 775"
            print "umask = 002"
            done=1
          }
          in_misc=0
        }
        { print }
        END {
          if (in_misc && !done) {
            print "host_whitelist_enabled = 1"
            print "host_whitelist = " wl
            print "permissions = 775"
            print "umask = 002"
          }
          if (!in_misc && !done) {
            print ""
            print "[misc]"
            print "host_whitelist_enabled = 1"
            print "host_whitelist = " wl
            print "permissions = 775"
            print "umask = 002"
          }
        }
      ' "$cfg" > "$cfg.tmp"
      mv "$cfg.tmp" "$cfg"
      ${pkgs.coreutils}/bin/chown ${config.services.sabnzbd.user}:${config.services.sabnzbd.group} "$cfg"
    '';
    serviceConfig.ExecStart = lib.mkForce "${lib.getBin config.services.sabnzbd.package}/bin/sabnzbd -d -f ${config.services.sabnzbd.configFile} -s 10.0.50.4:8080";
    serviceConfig.UMask = "0002";
    serviceConfig.EnvironmentFile = [ "/run/secrets/media.sabnzbd.env" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd 0775 sabnzbd media - -"
    "d /var/lib/sabnzbd/logs 0775 sabnzbd media - -"
    "f /var/lib/sabnzbd/logs/sabnzbd.log 0640 sabnzbd media - -"
  ];

  services.logrotate.settings.sabnzbd = {
    files = [
      "/var/lib/sabnzbd/logs/*.log"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "sabnzbd media";
  };

  environment.etc."alloy/sabnzbd.alloy".text = ''
    loki.source.file "sabnzbd" {
      targets = [
        {
          __path__ = "/var/lib/sabnzbd/logs/sabnzbd.log",
          job = "sabnzbd",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
