{ pkgs, lib, ... }:
{
  services.home-assistant = {
    enable = false;
    configDir = "/var/lib/home-assistant";

    config = {
      default_config = { };

      homeassistant = {
        name = "Vasudha";
        time_zone = "Europe/Stockholm";
        unit_system = "metric";
        temperature_unit = "C";
        latitude = "!secret homeassistant_latitude";
        longitude = "!secret homeassistant_longitude";
      };

      http = {
        server_host = "0.0.0.0";
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "10.0.50.7"
          "192.168.1.10"
        ];
      };

      wake_on_lan = {};

      prometheus = {};
    };

    extraComponents = [
      "adguard"
      # "alarm_control_panel"
      # "alarmdecoder"
      # "alert"
      # "androidtv"
      # "androidtv_remote"
      # "apache_kafka"
      # "api"
      # "apple_tv"
      # "application_credentials"
      # "automation"
      "backup"
      # "binary_sensor"
      "bluetooth"
      # "bluetooth_adapters"
      # "bluetooth_le_tracker"
      # "bluetooth_tracker"
      # "caldav"
      "calendar"
      # "camera"
      # "cast"
      # "cert_expiry"
      # "channels"
      # "cisco_webex_teams"
      # "citybikes"
      # "cloud"
      # "cloudflare"
      # "config"
      # "cpuspeed"
      # "currencylayer"
      "date"
      "datetime"
      "default_config"
      "denon"
      "denonavr"
      "device_automation"
      "device_sun_light_trigger"
      "device_tracker"
    ];

    customComponents = with pkgs.home-assistant-custom-components; [
      adaptive_lighting
      alarmo
      frigate
      scene_presets
      waste_collection_schedule
      
      # area_occupancy_detection - https://github.com/Hankanman/Area-Occupancy-Detection
      # battery_notes - https://github.com/andrew-codechimp/HA-Battery-Notes
      # fresh_intelli_sky - https://github.com/angoyd/freshintelliventHacs 
      # krisinfo - https://github.com/Nicxe/krisinformation
      # hass-plejd - https://github.com/thomasloven/hass-plejd
      # watchman - https://github.com/dummylabs/thewatchman
    ];

    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      advanced-camera-card
      # lg-webos-remote-control
      # mini-media-player
      mushroom
      # universal-remote-card

      # alarmo_card - https://github.com/nielsfaber/alarmo-card
    ];

    # integrations = [
    #   adguardhome
    #   alarmo
    #   backup
    #   batterynotes
    #   bluetooth
    #   denon_avr_networks
    #   denon_heos
    #   electricity_maps
    #   fresh_intelli_sky
    #   frigate
    #   google_cast
    #   govee
    #   hacs
    #   home_assistant_connect_zbt1
    #   homeassistnat_supervisor
    #   homekit_bridge
    #   ibeacon_tracker
    #   jellyfin
    #   lg_webos_tv
    #   local_ip_address
    #   metrological institute
    #   mobile_app
    #   moon
    #   mqtt
    #   music_assistant
    #   plejd_ble
    #   proximity
    #   radarr
    #   radio_browser
    #   rpi_power
    #   sabnzbd
    #   scene_presets
    #   season
    #   shopping_list
    #   sonarr
    #   sun
    #   system_monitor
    #   tasmota
    #   upnp/igd
    #   waste_collection_schedule
    #   watchman
    #   withings
    #   yale_access_bluetooth
    #   zigbee_automation 
    # ]

    # https://www.home-assistant.io/integrations/{}
    # extraComponents = [
    #   "adguard"
    #   "cast"
    #   "denonavr"
    #   "github"
    #   "govee_ble"
    #   "govee_light_local"
    #   "heos"
    #   "homeassistant_sky_connect"
    #   "homekit"
    #   "ibeacon"
    #   "jellyfin"
    #   "lidarr"
    #   "mqtt"
    #   "music_assistant"
    #   "prowlarr"
    #   "radarr"
    #   "radio_browser"
    #   "sabnzbd"
    #   "sonarr"
    #   "sun"
    #   "tasmota"
    #   "webostv"
    #   "withings"
    #   "yale"
    #   "yalexs_ble"
    #   "zha"
    # ];

    # extraPackages = python3Packages:
    #   let
    #     opt = name:
    #       if builtins.hasAttr name python3Packages then
    #         builtins.getAttr name python3Packages
    #       else
    #         null;
    #     optList = names: builtins.filter (pkg: pkg != null) (map opt names);
    #   in
    #   optList [
    #     "adguardhome"
    #     "aioelectricitymaps"
    #     "aiogithubapi"
    #     "aiopyarr"
    #     "aiowebostv"
    #     "aiowithings"
    #     "denonavr"
    #     "ephem"
    #     "getmac"
    #     "govee-api-laggat"
    #     "ha-silabs-firmware-client"
    #     "hatasmota"
    #     "ibeacon-ble"
    #     "isal"
    #     "jellyfin-apiclient-python"
    #     "music-assistant-client"
    #     "paho-mqtt"
    #     "prettytable"
    #     "pychromecast"
    #     "pyfreshintellivent"
    #     "pyhap"
    #     "pyheos"
    #     "pyplejd"
    #     "pysabnzbd"
    #     "radios"
    #     "titlecase"
    #     "yalexs-ble"
    #     "zha"
    #     "zlib-ng"
    #   ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/home-assistant 0750 home-assistant home-assistant - -"
  ];
}
