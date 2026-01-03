{
  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;
      server = {
        http_listen_address = "10.0.50.2";
        http_listen_port = 3100;
      };
      common = {
        instance_addr = "10.0.50.2";
        path_prefix = "/var/lib/loki";
        storage = {
          filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
      };
      schema_config.configs = [
        {
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];
    };
  };

  systemd.services.loki = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
