{
  # Shared between sutala's and surasa's AdGuard so both resolve the same exceptions.
  flake.lib.dns-allowlist = {
    domains = [
      # Legit Sonarr/Radarr scene-numbering API.
      "thexem.info"
      # Akashvani (All India Radio) streams via BitGravity CDN.
      "air.pc.cdn.bitgravity.com"
      "airhlspush.pc.cdn.bitgravity.com"
      # Binimum lyrics API (Tubifarry in Lidarr) redirects here.
      "lrc.red"
    ];

    # Also blocked by Cloudflare's family upstream, which an AdGuard allow rule can't override.
    familyBypass = [ ];
  };
}
