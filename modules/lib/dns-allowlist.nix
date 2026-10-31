{
  # Shared between sutala's and surasa's AdGuard so both resolve the same exceptions.
  flake.lib.dns-allowlist = {
    domains = [
      # Legit Sonarr/Radarr scene-numbering API.
      "thexem.info"
      # AIOStreams addon hosts that blocklists resolve to 0.0.0.0 (ECONNREFUSED).
      "yastream.tamthai.de"
      "torrent-catalogs.strem.fun"
      "torrentgalaxy.one"
      "comet.feels.legal"
      "knaben.org"
      "remuxdb.1632022.xyz"
      "releases.moe"
      # Akashvani (All India Radio) streams via BitGravity CDN.
      "air.pc.cdn.bitgravity.com"
      "airhlspush.pc.cdn.bitgravity.com"
      "cdncache.bitg.net"
      # Binimum lyrics API (Tubifarry in Lidarr) redirects here.
      "lrc.red"
    ];

    # Also blocked by Cloudflare's family upstream, which an AdGuard allow rule can't override.
    familyBypass = [
      "yastream.tamthai.de"
      "knaben.org"
      "remuxdb.1632022.xyz"
    ];
  };
}
