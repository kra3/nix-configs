{
  flake.homeManagerModules.home-log-tools = { pkgs, ... }: {
    home.packages = [
      pkgs.miller # mlr — CSV/TSV/JSON structured-data processor
      pkgs.angle-grinder # agrind — log query/aggregation pipeline
      pkgs.hl-log-viewer # hl — structured-log viewer
    ];
  };
}
