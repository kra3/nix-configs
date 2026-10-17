{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      avahiCompat = pkgs.avahi.override { withLibdnssdCompat = true; };

      pin = builtins.fromJSON (builtins.readFile ./sendspin-cli.json);
      version = lib.removePrefix "v" pin.version;
    in
    {
      packages = lib.optionalAttrs (pin.assets ? ${system}) {
        # The release binary: building from source fetches sendspin-cpp and its dependencies at configure time.
        sendspin-cli = pkgs.stdenv.mkDerivation {
          pname = "sendspin-cli";
          inherit version;
          src = pkgs.fetchurl {
            url = "https://github.com/${pin.repo}/releases/download/${pin.version}/sendspin-cli-${version}-linux-${pin.assets.${system}.arch}.tar.gz";
            inherit (pin.assets.${system}) hash;
          };
          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = [
            pkgs.alsa-lib
            pkgs.portaudio
            pkgs.libpulseaudio
            pkgs.pipewire
            avahiCompat
            pkgs.stdenv.cc.cc.lib
          ];
          installPhase = "install -Dm755 usr/local/bin/sendspin-cli $out/bin/sendspin-cli";
          meta.platforms = builtins.attrNames pin.assets;
        };
      };
    };
}
