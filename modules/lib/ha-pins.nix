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
        in
        {
          tree = pkgs.runCommand name { } ''
            mkdir -p $out
            src=${tarball p}/${p.subpath}
            if [ -d "$src" ]; then cp -r "$src"/. $out; else cp "$src" $out; fi
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
