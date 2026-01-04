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
      whitelist="sabnzbd.karunagath.in,10.0.50.4,127.0.0.1,localhost"
      ${pkgs.gawk}/bin/awk -v wl="$whitelist" '
        BEGIN { in_misc=0; done=0 }
        /^\[misc\]$/ { print; in_misc=1; next }
        in_misc && /^\[/ {
          if (!done) {
            print "host_whitelist_enabled = 1"
            print "host_whitelist = " wl
            done=1
          }
          in_misc=0
        }
        { print }
        END {
          if (in_misc && !done) {
            print "host_whitelist_enabled = 1"
            print "host_whitelist = " wl
          }
          if (!in_misc && !done) {
            print ""
            print "[misc]"
            print "host_whitelist_enabled = 1"
            print "host_whitelist = " wl
          }
        }
      ' "$cfg" > "$cfg.tmp"
      mv "$cfg.tmp" "$cfg"
      ${pkgs.coreutils}/bin/chown ${config.services.sabnzbd.user}:${config.services.sabnzbd.group} "$cfg"
    '';
    serviceConfig.ExecStart = lib.mkForce "${lib.getBin config.services.sabnzbd.package}/bin/sabnzbd -d -f ${config.services.sabnzbd.configFile} -s 10.0.50.4:8080";
    serviceConfig.EnvironmentFile = [ "/run/secrets/media.sabnzbd.env" ];
  };
}
