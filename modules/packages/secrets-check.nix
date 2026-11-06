{
  # Fails `nix flake check` if any file under secrets/ (other than the README) lacks sops
  # metadata, i.e. was committed before `sops -e`. gitleaks skips the encrypted files, so this
  # is what catches a plaintext secret landing there.
  perSystem =
    { pkgs, ... }:
    {
      checks.secrets-encrypted = pkgs.runCommand "secrets-encrypted" { } ''
        status=0
        for f in ${../../secrets}/*; do
          case "$(basename "$f")" in
            README.md) continue ;;
          esac
          if ! grep -qE '"sops"[[:space:]]*:|^sops:' "$f"; then
            echo "not sops-encrypted: secrets/$(basename "$f")" >&2
            status=1
          fi
        done
        [ "$status" -eq 0 ] && touch "$out"
        exit "$status"
      '';
    };
}
