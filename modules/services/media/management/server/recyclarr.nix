{
  services.recyclarr = {
    enable = false;
    configuration = { };
  };

  systemd.services.recyclarr.serviceConfig.LoadCredential = [ ];
}
