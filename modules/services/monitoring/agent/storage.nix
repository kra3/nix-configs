{
  systemd.tmpfiles.rules = [
    "d /srv/appdata/monitoring 0755 root root - -"
    "d /srv/appdata/monitoring/grafana 0755 root root - -"
    "d /srv/databases/monitoring 0755 root root - -"
    "d /srv/databases/monitoring/prometheus 0755 root root - -"
    "d /srv/databases/monitoring/loki 0755 root root - -"
  ];
}
