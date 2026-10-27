{
  perSystem =
    { pkgs, ... }:
    {
      checks.ha-lint =
        pkgs.runCommand "ha-lint" { nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.pyyaml ])) ]; }
          ''
            python3 ${./lint.py} ${./ha-config}
            touch $out
          '';
    };
}
