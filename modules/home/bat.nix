{
  flake.homeManagerModules.home-bat = { ... }: {
    programs.bat = {
      enable = true;
      config = {
        # Show line numbers, Git modifications and file header (but no grid)
        style = "numbers,changes,header";

        # Use italic text on the terminal (not supported on all terminals)
        italic-text = "always";

        # Add mouse scrolling support in less (does not work with all terminals)
        pager = "less -FR";

        tabs = "4";

        map-syntax = [
          "*.h:C++"           # Use C++ syntax for .h header files
          "*.tf:Terraform"    # Use Terraform syntax for .tf files
          "*.yml:YAML"        # Use YAML syntax for .yml files
        ];
      };
    };
  };
}
