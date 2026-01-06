{
  services.prometheus = {
    enable = true;
    listenAddress = "10.0.50.2";
    port = 9090;
    globalConfig = {
      scrape_interval = "15s";
    };
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:9090" ];
            labels.instance = "monitoring";
          }
        ];
      }
      {
        job_name = "node-host";
        static_configs = [
          {
            targets = [ "10.0.50.1:9100" ];
            labels.instance = "sutala";
          }
        ];
      }
      {
        job_name = "node-containers";
        static_configs = [
          {
            targets = [ "10.0.50.2:9100" ];
            labels.container = "monitoring";
            labels.instance = "monitoring";
          }
          {
            targets = [ "10.0.50.4:9100" ];
            labels.container = "media-mgmt";
            labels.instance = "media-mgmt";
          }
          {
            targets = [ "10.0.50.6:9100" ];
            labels.container = "media-play";
            labels.instance = "media-play";
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          {
            targets = [ "10.0.50.1:9113" ];
            labels.instance = "sutala";
          }
        ];
      }
      {
        job_name = "unbound";
        static_configs = [
          {
            targets = [ "10.0.50.1:9167" ];
            labels.instance = "sutala";
          }
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          {
            targets = [ "10.0.50.1:9134" ];
            labels.instance = "sutala";
          }
        ];
      }
    ];
  };

  systemd.services.prometheus = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
