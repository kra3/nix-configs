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

# Print the hosts' drvPaths as JSON. Kept simple and deterministic —
# useful for confirming a change's actual effect on the built system.
drv:
    #!/usr/bin/env bash
    set -euo pipefail
    sutala=$(nix eval --raw .#nixosConfigurations.sutala.config.system.build.toplevel.drvPath)
    macwork=$(nix eval --raw .#darwinConfigurations.mac-work.system.drvPath)
    jq -n \
        --arg sutala "$sutala" \
        --arg macwork "$macwork" \
        '{"nixosConfigurations.sutala": $sutala, "darwinConfigurations.mac-work.system": $macwork}'

# Local check: flake check, then print the hosts' drvPaths.
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

# Pre-pulls quadlet images from a built closure so a container restart during switch never stalls on a network pull.
_prepull-images result_path target="":
    #!/usr/bin/env bash
    set -euo pipefail
    images=$(grep -h '^Image=' {{result_path}}/etc/containers/systemd/*.container 2>/dev/null | sed 's/^Image=//' | sort -u)
    if [ -z "$images" ]; then
        exit 0
    fi
    while IFS= read -r img; do
        if [ -z "{{target}}" ]; then
            echo "pre-pulling $img"
            sudo podman pull "$img"
        else
            echo "pre-pulling $img on {{target}}"
            ssh {{target}} sudo podman pull "$img"
        fi
    done <<< "$images"

switch host=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        darwin-rebuild switch --flake .#{{host}}
    else
        nixos-rebuild build --flake .#{{host}}
        just _prepull-images ./result
        nixos-rebuild switch --flake .#{{host}}
    fi

switch-remote host=default_host target=default_host build_host=target:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        echo "switch-remote is not supported for darwin hosts (darwin-rebuild has no --target-host/--build-host equivalent); run 'just switch {{ host }}' on the host directly." >&2
        exit 1
    fi
    nixos-rebuild build --flake .#{{host}} --target-host {{target}} --build-host {{build_host}}
    just _prepull-images ./result {{target}}
    nixos-rebuild switch --flake .#{{host}} --target-host {{target}} --build-host {{build_host}} --use-remote-sudo --ask-sudo-password

# surasa has no DNS entry (relies on the "surasa" alias in ~/.ssh/config) and its weak
# CPU can't reliably build its own closure -- always build on sutala. Override target
# for the ethernet bootstrap IP instead of its normal wifi one when needed.
switch-surasa target="surasa":
    just switch-remote surasa {{target}} localhost

sops-edit file="secrets/secrets.yaml":
    sops {{file}}
