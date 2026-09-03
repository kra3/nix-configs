{
  flake.nixosModules.services-infrastructure-authelia =
  { config, lib, inputs, flakeLib, ... }:
  let
    domain = config.vars.acme.domain;
    configurationYmlContent = ''
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
            # Prowlarr's per-indexer download proxy (/<id>/download) carries its own apikey query-param auth but isn't under /api, so it needs its own bypass.
            - domain: 'prowlarr.${domain}'
              resources:
                - '^/[0-9]+/download([/?].*)?$'
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
            # Grafana reads role_attribute_path from the ID token only, which
            # is normally userinfo-only for "groups" — so embed it here too.
            claims_policies:
              id_token_groups:
                id_token:
                  - 'groups'
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
              - client_id: 'grafana'
                client_name: 'Grafana'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.grafana.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                claims_policy: 'id_token_groups'
                redirect_uris:
                  - 'https://grafana.${domain}/login/generic_oauth'
                scopes:
                  - 'openid'
                  - 'profile'
                  - 'email'
                  - 'groups'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
              - client_id: 'ghostfolio'
                client_name: 'Ghostfolio'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.ghostfolio.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                # Ghostfolio always sends creds via POST body, not a header.
                token_endpoint_auth_method: 'client_secret_post'
                redirect_uris:
                  - 'https://ghostfolio.${domain}/api/auth/oidc/callback'
                scopes:
                  - 'openid'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
              - client_id: 'actualbudget'
                client_name: 'Actual Budget'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.actualbudget.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                redirect_uris:
                  - 'https://actualbudget.${domain}/openid/callback'
                scopes:
                  - 'openid'
                  - 'profile'
                  - 'email'
                  - 'groups'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
              # one_factor not two_factor (Authelia's own guide default): no
              # second factor is configured on this deployment.
              - client_id: 'audiobookshelf'
                client_name: 'Audiobookshelf'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.audiobookshelf.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                require_pkce: true
                pkce_challenge_method: 'S256'
                redirect_uris:
                  - 'https://audiobookshelf.${domain}/auth/openid/callback'
                  - 'https://audiobookshelf.${domain}/auth/openid/mobile-redirect'
                  # ABS prefixes its own subfolder even though this vhost
                  # serves it at the root, not /audiobookshelf.
                  - 'https://audiobookshelf.${domain}/audiobookshelf/auth/openid/callback'
                  - 'https://audiobookshelf.${domain}/audiobookshelf/auth/openid/mobile-redirect'
                  - 'audiobookshelf://oauth'
                scopes:
                  - 'openid'
                  - 'profile'
                  - 'email'
                  - 'groups'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
                access_token_signed_response_alg: 'none'
                userinfo_signed_response_alg: 'none'
              # Provider name "authelia", set by hand in the SSO-Auth plugin's
              # own config (see jellyfin.nix), must match this redirect path.
              - client_id: 'jellyfin'
                client_name: 'Jellyfin'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.jellyfin.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                require_pkce: true
                pkce_challenge_method: 'S256'
                token_endpoint_auth_method: 'client_secret_post'
                redirect_uris:
                  - 'https://jellyfin.${domain}/sso/OID/redirect/authelia'
                scopes:
                  - 'openid'
                  - 'profile'
                  - 'email'
                  - 'groups'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
                access_token_signed_response_alg: 'none'
                userinfo_signed_response_alg: 'none'
              # Requires the hass-oidc-auth HACS integration, installed and
              # configured by hand in HA's own UI (no declarative path).
              - client_id: 'homeassistant'
                client_name: 'Home Assistant'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.homeassistant.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                claims_policy: 'id_token_groups'
                require_pkce: true
                pkce_challenge_method: 'S256'
                token_endpoint_auth_method: 'client_secret_post'
                redirect_uris:
                  - 'https://ha.${domain}/auth/oidc/callback'
                scopes:
                  - 'openid'
                  - 'profile'
                  - 'email'
                  - 'groups'
                grant_types:
                  - 'authorization_code'
                response_types:
                  - 'code'
              # Dashboard-only login (see aiostreams.nix), never the Stremio addon URLs.
              - client_id: 'aiostreams'
                client_name: 'AIOStreams'
                client_secret: '${config.sops.placeholder."authelia.oidc_clients.aiostreams.client_secret_hash"}'
                public: false
                authorization_policy: 'one_factor'
                # AIOStreams posts the client secret in the token body, not a header.
                token_endpoint_auth_method: 'client_secret_post'
                redirect_uris:
                  - 'https://aiostreams.${domain}/api/v1/auth/oidc/callback'
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
    usersDatabaseYmlContent = ''
        users:
          kra3:
            disabled: false
            displayname: 'kra3'
            password: '${config.sops.placeholder."authelia.users.kra3.password_hash"}'
            email: 'kra3@${domain}'
            groups:
              - 'admin'
          anjalipc:
            disabled: false
            displayname: 'anjalipc'
            password: '${config.sops.placeholder."authelia.users.anjalipc.password_hash"}'
            email: 'anjalipc@${domain}'
            groups:
              - 'family'
      '';
    # Neither string above embeds actual secret VALUES (sops placeholders
    # are stable tokens, substituted after this hash is computed), so this
    # changes exactly when the YAML content itself changes — not on every
    # secret rotation, but that's already the narrower, more common case
    # this exists for (see the container's environments below for why this
    # is needed at all).
    configHash = builtins.hashString "sha256" (configurationYmlContent + usersDatabaseYmlContent);
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
    sops.secrets."authelia.users.anjalipc.password_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.arcane.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.grafana.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.ghostfolio.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.actualbudget.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.audiobookshelf.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.jellyfin.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.homeassistant.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };
    sops.secrets."authelia.oidc_clients.aiostreams.client_secret_hash" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
    };

    sops.templates."authelia-configuration.yml" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
      content = configurationYmlContent;
    };

    sops.templates."authelia-users_database.yml" = {
      owner = "authelia";
      group = "authelia";
      mode = "0400";
      content = usersDatabaseYmlContent;
    };

    home-manager.users.authelia =
      { pkgs, ... }:
      {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = lib.mkDefault "25.11";

        virtualisation.quadlet.containers.authelia = {
          autoStart = true;
          containerConfig = {
            image = "ghcr.io/authelia/authelia:4.39.22";
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
              # Unused by Authelia itself — sops-nix re-renders the config
              # templates in place at a stable path (see the two
              # sops.templates above), so the container's own unit file
              # never changes on a config-only edit and nothing restarts
              # it. A systemd.user.paths watcher was tried here first, but
              # home-manager's activation script only ever restarts
              # changed *.service units, never .path units — it silently
              # never started at all. Embedding the content hash here
              # forces this *.service unit's own file to change (and thus
              # restart, via the same mechanism that already reliably
              # restarts every other quadlet unit on a real change)
              # whenever the config content does.
              RESTART_TRIGGER_CONFIG_HASH = configHash;
            };
          };
        };
      };
  };
}
