{ ... }:
{
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        settings = {
          allow_anonymous = false;
        };
        users = {
          kothu = {
            passwordFile = "/run/secrets/mqtt.password";
            acl = [ "readwrite #" ];
          };
        };
      }
    ];
  };

}
