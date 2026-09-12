{
  flake.homeManagerModules.home-music-beets =
    { config, ... }:
    {
      programs.beets = {
        enable = true;
        settings = {
          directory = "/srv/media/library/music/Western";
          library = "${config.home.homeDirectory}/.config/beets/western.db";
          plugins = [
            "chroma"
            "fetchart"
            "embedart"
            "lastgenre"
            "zero"
            "duplicates"
            "fromfilename"
            "edit"
          ];
          acoustid = {
            apikey = "@ACOUSTID_API_KEY@";
          };
          lastgenre = {
            source = "track";
            count = 1;
          };
          zero = {
            fields = [
              "comments"
            ];
          };
          embedart.maxwidth = 1000;
          import = {
            move = true;
            write = true;
          };
          paths = {
            default = "$albumartist/$album ($year)/$track - $title";
            comp = "$albumartist/$album ($year)/$track - $title";
          };
        };
      };

      # Second beets profile for Indian film soundtracks: invoked explicitly via
      # `beet -c ~/.config/beets/indian-film.yaml <command>`, not through programs.beets.
      home.file.".config/beets/indian-film.yaml".text = ''
        directory: /srv/media/library/music
        library: ${config.home.homeDirectory}/.config/beets/indian-film.db
        plugins: fetchart embedart zero duplicates fromfilename edit
        zero:
          fields: comments
        embedart:
          maxwidth: 1000
        import:
          move: yes
          write: yes
          autotag: no
        paths:
          default: "%the{$albumartist}/$album ($year)/$track - $title"
      '';
    };
}
