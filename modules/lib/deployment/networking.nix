{ lib, ... }:
{
  # Generate firewall rules for container interface
  mkContainerFirewall = { interface, tcp ? [], udp ? [] }: {
    networking.firewall.interfaces.${interface} = {
      allowedTCPPorts = tcp;
      allowedUDPPorts = udp;
    };
  };

  # Port forwarding helper
  mkPortForward = { sourcePort, destination, proto ? "tcp" }: {
    inherit sourcePort destination proto;
  };
}
