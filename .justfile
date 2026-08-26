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

# Print the three hosts' drvPaths as JSON (same shape as drv-lock.json).
# Kept simple and deterministic — this is what the verifier role runs.
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

# Local pre-commit gate equivalent to CI: flake check, confirm all three hosts
# eval, and confirm their drvPaths still match drv-lock.json. If a change is
# meant to move a drvPath, update drv-lock.json in the same commit.
eval: check
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(just drv)
    expected=$(jq -S 'del(._comment)' drv-lock.json)
    current_sorted=$(echo "$current" | jq -S '.')
    if [ "$current_sorted" != "$expected" ]; then
        echo "drvPaths differ from drv-lock.json:" >&2
        diff <(echo "$expected") <(echo "$current_sorted") >&2 || true
        echo "If this is an intentional change, update drv-lock.json in this commit." >&2
        exit 1
    fi
    echo "OK: all three hosts eval and match drv-lock.json"

build host=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        darwin-rebuild build --flake .#{{host}}
    else
        nixos-rebuild build --flake .#{{host}}
    fi

build-remote host=default_host target=default_host:
    nixos-rebuild build --flake .#{{host}} --target-host {{target}} --build-host {{target}}

switch host=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        darwin-rebuild switch --flake .#{{host}}
    else
        nixos-rebuild switch --flake .#{{host}}
    fi

switch-remote host=default_host target=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        echo "switch-remote is not supported for darwin hosts (darwin-rebuild has no --target-host/--build-host equivalent); run 'just switch {{ host }}' on the host directly." >&2
        exit 1
    fi
    nixos-rebuild switch --flake .#{{host}} --target-host {{target}} --build-host {{target}} --use-remote-sudo --ask-sudo-password

deploy host=default_host:
    colmena apply --on {{host}}

deploy-stop-first host=default_host:
    ssh {{host}}-root "systemctl stop 'podman-*.service' 2>/dev/null || true"
    colmena apply --on {{host}}

sops-edit file="secrets/secrets.yaml":
    sops {{file}}
