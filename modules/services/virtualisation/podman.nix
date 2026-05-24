{ ... }:
{
  virtualisation.podman = {
    enable = true;
    autoPrune = {
      enable = true;
      flags = [ "--all" ];
      dates = "daily";
    };
  };

  virtualisation.oci-containers.backend = "podman";
}
