{
  flake.overlays.smc-malayalam-fonts =
    final: prev:
    let
      # SMC ships prebuilt ttf/*.ttf alongside its .sfd sources, so no fontmake/fontforge build step is needed.
      mkSmcFont =
        {
          pname,
          version,
          repo,
          rev,
          sha256,
          license ? final.lib.licenses.ofl,
        }:
        final.stdenvNoCC.mkDerivation {
          inherit pname version;
          src = final.fetchzip {
            url = "https://gitlab.com/api/v4/projects/smc%2Ffonts%2F${repo}/repository/archive.tar.gz?sha=${rev}";
            inherit sha256;
          };
          dontBuild = true;
          installPhase = ''
            runHook preInstall

            install -Dm444 -t $out/share/fonts/truetype ttf/*.ttf
            install -Dm644 -t $out/etc/fonts/conf.d *.conf
            install -Dm644 -t $out/share/doc/${pname}-${version} LICENSE.txt

            runHook postInstall
          '';
          meta = {
            inherit license;
            description = "${pname} Malayalam typeface by Swathanthra Malayalam Computing";
            homepage = "https://gitlab.com/smc/fonts/${repo}";
            platforms = final.lib.platforms.all;
          };
        };
    in
    {
      smc-meera = mkSmcFont {
        pname = "smc-meera";
        version = "7.0.3";
        repo = "meera";
        rev = "Version7.0.3";
        sha256 = "0mwbvvissr7ccay5b622hilbfr9ybigb5823plwg0b5d59k7fywn";
      };
      smc-rachana = mkSmcFont {
        pname = "smc-rachana";
        version = "7.0.3";
        repo = "rachana";
        rev = "Version7.0.3";
        sha256 = "0r100pvk56y1s38nbv24d78s8nd7dkblgasbn8s887dzj6dps23d";
      };
      smc-anjalioldlipi = mkSmcFont {
        pname = "smc-anjalioldlipi";
        version = "7.1.2";
        repo = "anjalioldlipi";
        rev = "Version7.1.2";
        sha256 = "1pnmnhrp253d1rj2qy3z66msdsv4hfd6947z9hyp7n45pi6075xz";
      };
      smc-karumbi = mkSmcFont {
        pname = "smc-karumbi";
        version = "1.1.2";
        repo = "karumbi";
        rev = "Version1.1.2";
        sha256 = "0118sz7kphlnja8scj7cknws9rpqpxlwjk4zvr0k8vk9dwlzzvyr";
      };
    };
}
