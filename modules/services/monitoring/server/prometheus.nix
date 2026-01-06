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
          }
        ];
      }
      {
        job_name = "node-host";
        static_configs = [
          {
            targets = [ "10.0.50.1:9100" ];
          }
        ];
      }
      {
        job_name = "node-containers";
        static_configs = [
          {
            targets = [
              "10.0.50.2:9100"
              "10.0.50.4:9100"
              "10.0.50.6:9100"
            ];
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          {
            targets = [ "10.0.50.1:9113" ];
          }
        ];
      }
      {
        job_name = "unbound";
        static_configs = [
          {
            targets = [ "10.0.50.1:9167" ];
          }
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          {
            targets = [ "10.0.50.1:9134" ];
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
