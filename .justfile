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

build host=default_host:
    nixos-rebuild build --flake .#{{host}}

build-remote host=default_host target=default_host:
    nixos-rebuild build --flake .#{{host}} --target-host {{target}} --build-host {{target}}

switch host=default_host:
    nixos-rebuild switch --flake .#{{host}}

switch-remote host=default_host target=default_host:
    nixos-rebuild switch --flake .#{{host}} --target-host {{target}} --build-host {{target}} --use-remote-sudo --ask-sudo-password

deploy host=default_host:
    nix run github:zhaofengli/colmena -- apply --on {{host}}

sops-edit file="secrets/secrets.yaml":
    sops {{file}}
