{ config, ... }:
{
  users.users = {
    kra3 = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
  };
}
