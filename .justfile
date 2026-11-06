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

# Pre-pulls quadlet images from a built closure so a container restart during switch never stalls on a network pull; skips images already present locally, since tags here are pinned exact versions.
_prepull-images result_path target="":
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=( {{result_path}}/etc/containers/systemd/*.container )
    if [ ${#files[@]} -eq 0 ]; then
        exit 0
    fi
    images=$(grep -h '^Image=' "${files[@]}" | sed 's/^Image=//' | sort -u)
    while IFS= read -r img; do
        if [ -z "{{target}}" ]; then
            if sudo podman image exists "$img"; then
                echo "already present: $img"
            else
                echo "pre-pulling $img"
                sudo podman pull "$img"
            fi
        else
            if ssh {{target}} sudo podman image exists "$img"; then
                echo "already present on {{target}}: $img"
            else
                echo "pre-pulling $img on {{target}}"
                ssh {{target}} sudo podman pull "$img"
            fi
        fi
    done <<< "$images"

switch host=default_host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ host }}" = "mac-work" ]; then
        darwin-rebuild switch --flake .#{{host}}
    elif [ "{{ host }}" != "$(hostname)" ]; then
        just switch-remote {{host}} {{host}} localhost
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
    # --build-host means nixos-rebuild never writes a ./result symlink here, so capture the store path from stdout instead (it prints only that, by design, for scripting).
    result=$(nixos-rebuild build --flake .#{{host}} --target-host {{target}} --build-host {{build_host}})
    just _prepull-images "$result" {{target}}
    nixos-rebuild switch --flake .#{{host}} --target-host {{target}} --build-host {{build_host}} --sudo --ask-sudo-password

# surasa has no DNS entry (relies on the "surasa" alias in ~/.ssh/config) and its weak
# CPU can't reliably build its own closure -- always build on sutala. Override target
# for the ethernet bootstrap IP instead of its normal wifi one when needed.
switch-surasa target="surasa":
    just switch-remote surasa {{target}} localhost

sops-edit file="secrets/secrets.yaml":
    sops {{file}}

# One-time secret for services-second-brain-default (docs/second-brain.md): the deploy key for the
# vault hub repo. Idempotent; the key goes to sops on stdin, never argv.
second-brain-secrets file="secrets/secrets.yaml":
    #!/usr/bin/env bash
    set -euo pipefail
    file={{file}}
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    have() { sops decrypt --extract "[\"$1\"]" "$file" >/dev/null 2>&1; }
    put() { jq -Rs . | sops set --value-stdin "$file" "[\"$1\"]"; echo "  added $1"; }

    echo "== Deploy key for the vault hub repo"
    if have second-brain.git.deploy_key; then
      sops decrypt --extract '["second-brain.git.deploy_key"]' "$file" > "$tmp/key"; chmod 600 "$tmp/key"
    else
      ssh-keygen -q -t ed25519 -N "" -C "second-brain@sutala" -f "$tmp/key"
      put second-brain.git.deploy_key < "$tmp/key"
    fi
    echo "  add this as a deploy key WITH write access on the vault repo:"
    echo "    $(ssh-keygen -y -f "$tmp/key")"

# List tools the enabled Neovim extras expect and flag any missing from PATH.
nvim-check-tools:
    nvim --headless -c "luafile modules/home/neovim/check-tools.lua"
