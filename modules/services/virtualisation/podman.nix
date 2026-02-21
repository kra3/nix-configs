{ ... }:
{
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerSocket.enable = true;
  };

  virtualisation.oci-containers.backend = "podman";
}
