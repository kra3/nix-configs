{ lib, ... }:
{
  # Helper to pass host config to container
  mkContainerImports = imports: {
    config = {
      inherit imports;
    };
  };
}
