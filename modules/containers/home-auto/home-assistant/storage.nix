{
  flake.nixosModules.containers-home-auto-home-assistant-storage = { ... }:
  {
    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/home-assistant 0750 root root - -"
      "d /srv/appdata/home-auto/home-assistant/data 0750 root root - -"
  
      # Seed writable runtime files from repo on first deploy only (C = copy if absent)
      "C /srv/appdata/home-auto/home-assistant/data/automations.yaml - - - - ${./ha-config/automations.yaml}"
      "C /srv/appdata/home-auto/home-assistant/data/scripts.yaml - - - - ${./ha-config/scripts.yaml}"
      "C /srv/appdata/home-auto/home-assistant/data/scenes.yaml - - - - ${./ha-config/scenes.yaml}"
    ];
  };
}
