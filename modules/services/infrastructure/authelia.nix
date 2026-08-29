{
  flake.nixosModules.services-infrastructure-authelia =
  { config, lib, inputs, flakeLib, ... }:
  let
    domain = config.vars.acme.domain;
  in
  {
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
    # (AUTHELIA_CONFIGURATION_FILTERS=template below).
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
          default_policy: 'deny'
          rules: []

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
                grant_types:
                  - 'authorization_code'
                  - 'refresh_token'
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
          drpc:
            disabled: false
            displayname: 'drpc'
            password: '${config.sops.placeholder."authelia.users.drpc.password_hash"}'
      '';
    };

    home-manager.users.authelia =
      { pkgs, ... }:
      {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = lib.mkDefault "25.11";

        systemd.user.sockets.podman = {
          Unit.Description = "Podman API Socket";
          Socket = {
            ListenStream = "%t/podman/podman.sock";
            SocketMode = "0660";
          };
          Install.WantedBy = [ "sockets.target" ];
        };
        systemd.user.services.podman = {
          Unit = {
            Description = "Podman API Service";
            Requires = [ "podman.socket" ];
            After = [ "podman.socket" ];
          };
          Service = {
            Delegate = "true";
            Type = "exec";
            KillMode = "process";
            ExecStart = "${pkgs.podman}/bin/podman system service";
          };
        };

        virtualisation.quadlet.containers.authelia = {
          autoStart = true;
          containerConfig = {
            image = "ghcr.io/authelia/authelia:4.39.20";
            publishPorts = [ "127.0.0.1:9091:9091" ];
            userns = "keep-id";
            volumes = [
              "${config.sops.templates."authelia-configuration.yml".path}:/config/configuration.yml:ro"
              "${config.sops.templates."authelia-users_database.yml".path}:/config/users_database.yml:ro"
              "${config.sops.secrets."authelia.oidc_issuer_private_key".path}:/config/secrets/oidc_issuer_private_key.pem:ro"
              "/srv/authelia:/data"
            ];
            environments = {
              AUTHELIA_CONFIGURATION_FILTERS = "template";
            };
          };
        };
      };
  };
}
