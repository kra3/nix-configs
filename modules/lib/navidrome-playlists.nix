{ lib, ... }:
{
  flake.lib.navidrome-playlists.mkPlaylistsDir =
    pkgs:
    let
      languageMix = language: {
        all = [ { is = { inherit language; }; } ];
        sort = "random";
        limit = 200;
      };
      mix = rule: {
        all = [ rule ];
        sort = "random";
        limit = 200;
      };
      pathMix = path: mix { contains.filepath = path; };
      genreMix = genres: mix { any = map (genre: { is = { inherit genre; }; }) genres; };
      navidromeSmartPlaylists = {
        "Carnatic Mix" = pathMix "Classical/Carnatic/";
        "Hindustani Mix" = pathMix "Classical/Hindustani/";
        "Western Classical Mix" = pathMix "Classical/Western/";
        "Opera & Choral" = genreMix [
          "Opera"
          "Requiem"
          "Mass"
        ];
        "Throwback 90s-00s" = {
          all = [
            {
              inTheRange.year = [
                1990
                2009
              ];
            }
          ];
          sort = "random";
          limit = 200;
        };
        "Malayalam Devotional" = {
          all = [
            { contains.filepath = "Devotional/"; }
            { is.language = "mal"; }
          ];
          sort = "random";
          limit = 200;
        };
        "Tamil Devotional" = {
          all = [
            { contains.filepath = "Devotional/"; }
            { is.language = "tam"; }
          ];
          sort = "random";
          limit = 200;
        };
        "Sanskrit Stotras" = {
          all = [
            { contains.filepath = "Devotional/"; }
            { is.language = "san"; }
          ];
          sort = "random";
          limit = 200;
        };
        "Hindi Mix" = languageMix "hin";
        "Tamil Mix" = languageMix "tam";
        "Malayalam Mix" = languageMix "mal";
        "Favourites" = {
          all = [ { is.loved = true; } ];
          sort = "dateLoved";
          order = "desc";
        };
      };
      personal = [ "Favourites" ];
      # Owner is set to this user by hand in Navidrome's Playlists view; the .nsp can't declare it.
      extraUsers = [ "drpc" ];
      playlists =
        navidromeSmartPlaylists
        // lib.listToAttrs (
          lib.concatMap (
            user:
            map (name: {
              name = "${name} (${user})";
              value = navidromeSmartPlaylists.${name};
            }) personal
          ) extraUsers
        );
    in
    pkgs.linkFarm "navidrome-smart-playlists" (
      lib.mapAttrsToList (name: rules: {
        name = "${name}.nsp";
        path = pkgs.writeText "${name}.nsp" (
          builtins.toJSON (
            {
              inherit name;
              public = !(lib.any (p: lib.hasPrefix p name) personal);
            }
            // rules
          )
        );
      }) playlists
    );
}
