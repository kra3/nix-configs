#!/usr/bin/env bash
# Recomputes every asset hash in sendspin-cli.json from its repo/version/arch. Needs nix + jq.
set -euo pipefail

file="${1:-modules/packages/sendspin-cli.json}"
tmp="$(mktemp)"
cp "$file" "$tmp"
repo="$(jq -r .repo "$file")"
version="$(jq -r .version "$file")"

for system in $(jq -r '.assets | keys[]' "$file"); do
  arch="$(jq -r --arg s "$system" '.assets[$s].arch' "$file")"
  url="https://github.com/$repo/releases/download/$version/sendspin-cli-${version#v}-linux-$arch.tar.gz"
  hash="$(nix store prefetch-file --json "$url" | jq -r .hash)"
  jq --arg s "$system" --arg h "$hash" '.assets[$s].hash = $h' "$tmp" >"$tmp.new"
  mv "$tmp.new" "$tmp"
  echo "$system $version $hash"
done

mv "$tmp" "$file"
