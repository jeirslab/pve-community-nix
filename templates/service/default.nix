# __NAME__ — __DESCRIPTION__
#
# The contract below is the service's whole public surface: it drives the
# NixOS options every service gets (enable, environmentFile, openFirewall),
# the container image, the compose snippet, the docs page and the parity
# test. Field reference: lib/contract.nix.
{ svc }:

svc.mkService {
  name = "__NAME__";

  contract = {
    description = "__DESCRIPTION__";
    homepage = null; # "https://…"

    # "extracted": lift the systemd unit of the NixOS module into the image.
    # "modular":   run a nixpkgs modular service (system.services) directly.
    # Record why in upstream.json → decision.reason.
    approach = "extracted";
    unit = "__NAME__"; # systemd service to lift (approach = "extracted")
    # modularService = "__NAME__"; # name under system.services (approach = "modular")

    ports = [
      # { port = 8080; description = "Web UI"; }
    ];

    # Every variable a user may set. On NixOS they come from environmentFile,
    # in a container from -e / env_file / compose. A default applies on both.
    env = {
      # EXAMPLE_VAR = {
      #   description = "What it controls.";
      #   default = "value";      # or: required = true;
      #   secret = false;
      # };
    };

    # 2xx once the service is up; used by the image, compose and parity test.
    healthcheck = {
      port = 8080;
      path = "/";
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
