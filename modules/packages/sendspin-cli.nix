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

      release = {
        aarch64-linux = {
          arch = "arm64";
          hash = "sha256-SQNbJ50UDQmcibSWg3N5vZvlDss6if5iorYMj1JD4mQ=";
        };
        x86_64-linux = {
          arch = "x86_64";
          hash = "sha256-FeUjZKvjbIKbBNif98M0f/vVxZ0bmJYFvYBRx/QCgS4=";
        };
      };
    in
    {
      packages = lib.optionalAttrs (release ? ${system}) {
        # The release binary: building from source fetches sendspin-cpp and its dependencies at configure time.
        sendspin-cli = pkgs.stdenv.mkDerivation rec {
          pname = "sendspin-cli";
          version = "0.3.0";
          src = pkgs.fetchurl {
            url = "https://github.com/Sendspin/sendspin-cpp-cli/releases/download/v${version}/sendspin-cli-${version}-linux-${release.${system}.arch}.tar.gz";
            inherit (release.${system}) hash;
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
          meta.platforms = builtins.attrNames release;
        };
      };
    };
}
