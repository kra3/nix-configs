{
  flake.homeManagerModules.home-music-lidarr-beets-retag = {
    # Beets Integration Pattern 3 (Servarr Wiki, lidarr/beets-integration.md):
    # Lidarr keeps its own tag-writer on (Write Audio Tags = All files, keep in
    # sync with MusicBrainz) and fires On Track Retag after every write. The
    # actual beet invocation happens on the host via
    # services-media-lidarr-beets-webhook (Lidarr runs in a podman container
    # and can't see the host's beet install) -- this overlay is what that
    # webhook passes as a second --config so move/copy stay off, since beets
    # must never fight Lidarr over where the file lives.
    home.file.".config/beets-lidarr-hook/overlay.yaml".text = ''
      import:
        move: no
        copy: no
        write: yes
        autotag: yes
        quiet: yes
    '';
  };
}
