#!/usr/bin/env bash
# Recomputes every hash in ha-pins.json from its repo/version/kind. Needs nix + jq.
set -euo pipefail

file="${1:-modules/services/home-automation/home-assistant/ha-pins.json}"
tmp="$(mktemp)"
cp "$file" "$tmp"

while IFS=$'\t' read -r group name repo version kind asset; do
  case "$kind" in
    tree)
      url="https://github.com/$repo/archive/refs/tags/$version.tar.gz"
      hash="$(nix store prefetch-file --unpack --json "$url" | jq -r .hash)"
      ;;
    zip | file)
      url="https://github.com/$repo/releases/download/$version/$asset"
      hash="$(nix store prefetch-file --json "$url" | jq -r .hash)"
      ;;
    *)
      echo "unknown kind '$kind' for $group.$name" >&2
      exit 1
      ;;
  esac
  jq --arg g "$group" --arg n "$name" --arg h "$hash" '.[$g][$n].hash = $h' "$tmp" >"$tmp.new"
  mv "$tmp.new" "$tmp"
  echo "$group.$name $version $hash"
done < <(jq -r 'to_entries[] | .key as $g | .value | to_entries[] | [$g, .key, .value.repo, .value.version, .value.kind, (.value.asset // "")] | @tsv' "$file")

mv "$tmp" "$file"
