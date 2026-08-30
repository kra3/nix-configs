{
  flake.nixosModules.services-infrastructure-authelia =
  { config, lib, inputs, flakeLib, ... }:
  let
    domain = config.vars.acme.domain;
  in
  {
    # Authelia OIDC identity provider. Runs rootless under its own dedicated
    # user (uid 2301, modules/users/authelia.nix) for the same reasons Arcane
    # does (see modules/services/virtualisation/arcane.nix). Currently wired
    # to exactly one OIDC client (Arcane) as a pilot.
    services.nginx.virtualHosts."auth.${domain}" = flakeLib.nginx.mkProxyVhost {
      domain = domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:9091";
    };

    # Sibling of /srv/appdata for the same reason as /srv/arcane (see
    # modules/services/virtualisation/arcane.nix): /srv/appdata's ZFS
    # dataset has no acltype=posixacl, so ACLs for a non-root app there
    # silently no-op.
    systemd.tmpfiles.rules = [
      "d /srv/authelia 0750 authelia authelia - -"
    ];

    sops.secrets."authelia.session_secret" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.storage_encryption_key" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_hmac_secret" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.reset_password_jwt_secret" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    # Not templated like the secrets above: it's a multi-line PEM, and
    # sops.templates does raw textual substitution with no YAML
    # re-indentation, which breaks block-scalar parsing for multi-line
    # values. Kept as its own file and pulled into configuration.yml via
    # Authelia's own `secret`/`mindent` config template function instead
    # (X_AUTHELIA_CONFIG_FILTERS=template below).
    sops.secrets."authelia.oidc_issuer_private_key" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.users.kra3.password_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.users.drpc.password_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.arcane.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };

    sops.templates."authelia-configuration.yml" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
      content = ''
        theme: 'auto'

        server:
          address: 'tcp://:9091/'

        log:
          level: 'info'

        identity_validation:
          reset_password:
            jwt_secret: '${config.sops.placeholder."authelia.reset_password_jwt_secret"}'

        authentication_backend:
          password_reset:
            disable: true
          password_change:
            disable: true
          file:
            path: '/config/users_database.yml'
            password:
              algorithm: 'argon2'
              argon2:
                variant: 'argon2id'
                iterations: 3
                memory: 65536
                parallelism: 4
                key_length: 32
                salt_length: 16

        access_control:
          default_policy: 'one_factor'
          rules:
            # These apps' /api paths carry their own API-key auth and are
            # legitimately called by external clients that don't hold an
            # Authelia session (mobile companion apps, automation scripts,
            # etc.) — bypassing Authelia here doesn't weaken anything, it
            # just stops Authelia from *also* demanding a session cookie on
            # top of the app's own key. Everything else on these domains
            # (the UI) still falls through to default_policy above.
            - domain:
                - 'radarr.${domain}'
                - 'sonarr.${domain}'
                - 'lidarr.${domain}'
                - 'prowlarr.${domain}'
                - 'bazarr.${domain}'
                - 'sabnzbd.${domain}'
              resources:
                - '^/api([/?].*)?$'
              policy: 'bypass'

        session:
          secret: '${config.sops.placeholder."authelia.session_secret"}'
          cookies:
            - domain: '${domain}'
              authelia_url: 'https://auth.${domain}'
              expiration: '1h'

        storage:
          encryption_key: '${config.sops.placeholder."authelia.storage_encryption_key"}'
          local:
            path: '/data/db.sqlite3'

        notifier:
          disable_startup_check: false
          filesystem:
            filename: '/data/notification.txt'

        identity_providers:
          oidc:
            hmac_secret: '${config.sops.placeholder."authelia.oidc_hmac_secret"}'
            jwks:
              - key_id: 'primary'
                algorithm: 'RS256'
                use: 'sig'
                key: {{ secret "/config/secrets/oidc_issuer_private_key.pem" | mindent 10 "|" | msquote }}
            clients:
              - client_id: 'arcane'
                client_name: 'Arcane'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.arcane.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                redirect_uris:
                  - 'https://oci.${domain}/auth/oidc/callback'
                scopes:
                  - 'openid'
                  - 'profile'
                  - 'email'
                  - 'groups'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
      '';
    };

    sops.templates."authelia-users_database.yml" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
      content = ''
        users:
          kra3:
            disabled: false
            displayname: 'kra3'
            password: '${config.sops.placeholder."authelia.users.kra3.password_hash"}'
            email: 'kra3@${domain}'
            groups:
              - 'admin'
          drpc:
            disabled: false
            displayname: 'drpc'
            password: '${config.sops.placeholder."authelia.users.drpc.password_hash"}'
            email: 'drpc@${domain}'
      '';
    };

    home-manager.users.authelia =
      { pkgs, ... }:
      {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = lib.mkDefault "25.11";

        # sops-nix re-renders these paths in place on every switch (the path
        # itself never changes, so the container's unit file doesn't change
        # either) — nothing restarts the container on its own. restartUnits
        # can't help here since it only ever runs a plain (system) `systemctl
        # restart`, and this is a `systemctl --user` unit under the authelia
        # user's own instance. Watch the paths directly and restart on
        # change instead.
        systemd.user.paths.authelia-config-reload = {
          Unit.Description = "Watch Authelia's rendered config/secrets for changes";
          Path.PathChanged = [
            config.sops.templates."authelia-configuration.yml".path
            config.sops.templates."authelia-users_database.yml".path
            config.sops.secrets."authelia.oidc_issuer_private_key".path
          ];
          Install.WantedBy = [ "paths.target" ];
        };
        systemd.user.services.authelia-config-reload = {
          Unit.Description = "Restart Authelia after its config changes";
          Service = {
            Type = "oneshot";
            ExecStart = "systemctl --user restart authelia.service";
          };
        };

        virtualisation.quadlet.containers.authelia = {
          autoStart = true;
          containerConfig = {
            image = "ghcr.io/authelia/authelia:4.39.20";
            publishPorts = [ "127.0.0.1:9091:9091" ];
            # Unlike Arcane, this container never talks to the podman socket
            # directly, so it doesn't need systemd.user.sockets/services.podman
            # (see arcane.nix) — quadlet-nix's generated container units work
            # without it by default.
            # If keep-id doesn't map cleanly onto Authelia's image the way it
            # does for Arcane's (proven), Authelia's official image separately
            # supports PUID/PGID env vars as a fallback, so its entrypoint
            # chowns /data itself.
            userns = "keep-id";
            volumes = [
              "${config.sops.templates."authelia-configuration.yml".path}:/config/configuration.yml:ro"
              "${config.sops.templates."authelia-users_database.yml".path}:/config/users_database.yml:ro"
              "${config.sops.secrets."authelia.oidc_issuer_private_key".path}:/config/secrets/oidc_issuer_private_key.pem:ro"
              "/srv/authelia:/data"
            ];
            environments = {
              X_AUTHELIA_CONFIG_FILTERS = "template";
            };
          };
        };
      };
  };
}
