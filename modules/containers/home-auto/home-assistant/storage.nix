{
  flake.nixosModules.containers-home-auto-home-assistant-storage = { ... }:
  {
    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/home-assistant 0750 root root - -"
      "d /srv/appdata/home-auto/home-assistant/data 0750 root root - -"

      # automations.yaml/scripts.yaml/scenes.yaml are bind-mounted read-only
      # straight from the Nix store in container.nix, so they're pure IaC —
      # no seeding needed or possible here.
      #
      # automations_experimental.yaml is the one spot HA's automation UI can
      # actually write to (see packages/experimental.yaml). Created once as
      # an empty list and never touched again, so nothing built in the UI is
      # ever clobbered by a deploy.
      "f /srv/appdata/home-auto/home-assistant/data/automations_experimental.yaml 0644 root root - []"
    ];
  };
}
