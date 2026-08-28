{
  flake.nixosModules.hardware-intel-igpu =
  # Intel iGPU support (VAAPI/QSV/OpenCL), scoped to hosts that actually have
  # one. sutala-only: import this from a host's configuration.nix, not from a
  # generic/global module -- it was previously applied to every host
  # (including aarch64-darwin mac-work) via the flake-wide overlay.
  { inputs, pkgs, ... }:
  {
    nixpkgs.overlays = [ inputs.self.overlays.default ];

    nixpkgs.config.permittedInsecurePackages = [
      "intel-media-sdk-23.2.2"
    ];

    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver # VAAPI driver for Gen9+ Intel iGPU (Comet Lake)
        # intel-vaapi-driver # legacy i965 VAAPI driver fallback

        libva-vdpau-driver # VAAPI to VDPAU translation layer
        libvdpau-va-gl # VDPAU on top of VAAPI/OpenGL

        intel-compute-runtime-legacy1 # OpenCL/oneAPI runtime for Intel iGPU
        level-zero # Level Zero loader for OpenVINO GPU

        intel-media-sdk # oneVPL runtime for Intel QSV pipelines
      ];
    };
  };
}
