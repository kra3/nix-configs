# Common repo tasks

set dotenv-load := false

default_host := "sutala"

default:
    @just --list

fmt:
    nix fmt

check:
    nix flake check

update:
    nix flake update

# Print the three hosts' drvPaths as JSON. Kept simple and deterministic —
# useful for confirming a change's actual effect on the built system.
drv:
    #!/usr/bin/env bash
    set -euo pipefail
    sutala=$(nix eval --raw .#nixosConfigurations.sutala.config.system.build.toplevel.drvPath)
    macwork=$(nix eval --raw .#darwinConfigurations.mac-work.system.drvPath)
    colmena=$(nix eval --raw .#colmenaHive.nodes.sutala.config.system.build.toplevel.drvPath)
    jq -n \
        --arg sutala "$sutala" \
        --arg macwork "$macwork" \
        --arg colmena "$colmena" \
        '{"nixosConfigurations.sutala": $sutala, "darwinConfigurations.mac-work.system": $macwork, "colmenaHive.nodes.sutala": $colmena}'

# Local check: flake check, then print all three hosts' drvPaths.
eval: check
    @just drv

build host=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        darwin-rebuild build --flake .#{{host}}
    else
        nixos-rebuild build --flake .#{{host}}
    fi

build-remote host=default_host target=default_host build_host=target:
    nixos-rebuild build --flake .#{{host}} --target-host {{target}} --build-host {{build_host}}

switch host=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        darwin-rebuild switch --flake .#{{host}}
    else
        nixos-rebuild switch --flake .#{{host}}
    fi

switch-remote host=default_host target=default_host build_host=target:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        echo "switch-remote is not supported for darwin hosts (darwin-rebuild has no --target-host/--build-host equivalent); run 'just switch {{ host }}' on the host directly." >&2
        exit 1
    fi
    nixos-rebuild switch --flake .#{{host}} --target-host {{target}} --build-host {{build_host}} --use-remote-sudo --ask-sudo-password

deploy host=default_host:
    colmena apply --on {{host}}

deploy-stop-first host=default_host:
    ssh {{host}}-root "systemctl stop 'podman-*.service' 2>/dev/null || true"
    colmena apply --on {{host}}

sops-edit file="secrets/secrets.yaml":
    sops {{file}}
