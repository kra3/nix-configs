{ lib, ... }:
{
  # Pinned HACS components, built from ha-pins.json; hashes are refreshed by .github/scripts/update-ha-pin-hashes.sh.
  flake.lib.ha-pins =
    pkgs:
    let
      pins = builtins.fromJSON (
        builtins.readFile ../services/home-automation/home-assistant/ha-pins.json
      );

      tarball =
        p:
        pkgs.fetchzip {
          url = "https://github.com/${p.repo}/archive/refs/tags/${p.version}.tar.gz";
          inherit (p) hash;
        };

      release =
        p:
        pkgs.fetchurl {
          url = "https://github.com/${p.repo}/releases/download/${p.version}/${p.asset}";
          inherit (p) hash;
        };

      build =
        name: p:
        let
          extra = lib.concatMapStringsSep "\n" (d: "mkdir -p $out/${d}") (p.extraDirs or [ ]);
          applyPatches = lib.concatMapStringsSep "\n" (
            pt:
            "(cd src && git apply ${lib.concatMapStringsSep " " (e: "--exclude=${e}") (pt.excludes or [ ])} ${
              pkgs.fetchurl { inherit (pt) url hash; }
            })"
          ) (p.patches or [ ]);
          requirements = lib.optionalString (p ? requirements) ''
            jq --argjson r '${builtins.toJSON p.requirements}' '.requirements = $r' $out/manifest.json > manifest.new
            cp manifest.new $out/manifest.json
          '';
        in
        {
          tree =
            pkgs.runCommand name
              {
                nativeBuildInputs = [
                  pkgs.git
                  pkgs.jq
                ];
              }
              ''
                cp -r ${tarball p} src
                chmod -R u+w src
                ${applyPatches}
                mkdir -p $out
                s=src/${p.subpath}
                if [ -d "$s" ]; then cp -r "$s"/. $out; else cp "$s" $out; fi
                ${requirements}
                ${extra}
              '';
          zip = pkgs.runCommand name { nativeBuildInputs = [ pkgs.unzip ]; } ''
            unzip -q ${release p} -d unpacked
            mkdir -p $out
            cp -r unpacked/${p.subpath or "."}/. $out
            ${extra}
          '';
          file = pkgs.runCommand name { } ''
            mkdir -p $out
            cp ${release p} $out/${p.asset}
            ${extra}
          '';
        }
        .${p.kind};
    in
    {
      integrations = lib.mapAttrs build pins.integrations;
      frontend = lib.mapAttrs build pins.frontend;
      frontendVersions = lib.mapAttrs (_: p: p.version) pins.frontend;
    };
}
