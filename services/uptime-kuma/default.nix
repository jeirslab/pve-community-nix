# uptime-kuma — Fancy self-hosted uptime monitoring tool
#
# The contract below is the service's whole public surface: it drives the
# NixOS options every service gets (enable, environmentFile, openFirewall),
# the container image, the compose snippet, the docs page and the parity
# test. Field reference: lib/contract.nix.
{ svc }:

svc.mkService {
  name = "uptime-kuma";

  contract = {
    description = "Fancy self-hosted uptime monitoring tool";
    homepage = "https://uptime.kuma.pet/";

    approach = "extracted";
    unit = "uptime-kuma";

    ports = [
      { port = 3001; description = "Web UI"; }
    ];

    env = {
      HOST = {
        description = "Listen address.";
        default = "0.0.0.0";
      };
      PORT = {
        description = "Web UI listen port.";
        default = "3001";
      };
      UPTIME_KUMA_DB_TYPE = {
        description = "Database type: sqlite or mariadb (for mariadb also set UPTIME_KUMA_DB_HOSTNAME, UPTIME_KUMA_DB_PORT, UPTIME_KUMA_DB_NAME, UPTIME_KUMA_DB_USERNAME, UPTIME_KUMA_DB_PASSWORD).";
        default = "sqlite";
      };
      UPTIME_KUMA_DB_PASSWORD = {
        description = "External database password (mariadb only).";
        secret = true;
      };
    };

    healthcheck = {
      port = 3001;
      path = "/api/entry-page";
    };
  };

  module = {
    imports = [
      ./options.nix
      ./configuration.nix
      ./scripts.nix
    ];
  };

  docker = import ./docker.nix;
  check = import ./check.nix;
  upstream = builtins.fromJSON (builtins.readFile ./upstream.json);
}
