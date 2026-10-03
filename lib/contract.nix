# The service contract: what every service declares about itself, in one
# fixed shape. It's the source for the NixOS options every service gets, the
# container image, the compose snippet, the docs page and the parity test,
# so none of those are written by hand per service and none can drift.
#
# Declared as module options so a wrong field is a type error at eval time,
# not a broken image later.
{ lib }:

let
  inherit (lib) mkOption types;

  port = types.submodule {
    options = {
      port = mkOption {
        type = types.port;
        description = "Port the service listens on (same inside the container and on a NixOS host).";
      };
      protocol = mkOption {
        type = types.enum [ "tcp" "udp" ];
        default = "tcp";
        description = "Transport protocol.";
      };
      description = mkOption {
        type = types.str;
        description = "What is served on this port (e.g. \"Web UI\").";
      };
    };
  };

  envVar = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "What the variable controls.";
      };
      default = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Value used when the variable isn't set. Applied the same way on both
          sides: as a systemd Environment= default on NixOS (an
          environmentFile still overrides it) and as an image default in the
          container (a runtime -e / env_file still overrides it).
        '';
      };
      required = mkOption {
        type = types.bool;
        default = false;
        description = "The service can't start without it and there is no sensible default.";
      };
      secret = mkOption {
        type = types.bool;
        default = false;
        description = "Holds a credential: never give it a default, keep it out of logs and docs examples.";
      };
      example = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Example value for the docs (never a real secret).";
      };
    };
  };
in
{
  options = {
    description = mkOption {
      type = types.str;
      description = "One line: what the service is.";
    };

    homepage = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Upstream project homepage.";
    };

    approach = mkOption {
      type = types.enum [ "extracted" "modular" ];
      description = ''
        How the container image is produced from the NixOS definition.
        `extracted`: evaluate the NixOS module and lift its systemd unit
        (ExecStart, environment, pre-start, state directories) into a
        single-process image. `modular`: the service is a nixpkgs modular
        service (system.services) whose process definition the image runs
        directly. Chosen per service; see upstream.json for why.
      '';
    };

    unit = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "systemd service the `extracted` approach lifts, without `.service`.";
    };

    modularService = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name under `system.services` for the `modular` approach.";
    };

    ports = mkOption {
      type = types.listOf port;
      default = [ ];
      description = "Ports the service listens on.";
    };

    env = mkOption {
      type = types.attrsOf envVar;
      default = { };
      description = ''
        Every environment variable a user may set, keyed by name. This is the
        whole configuration surface: on NixOS via `environmentFile`, in a
        container via -e / env_file / compose `environment`.
      '';
    };

    healthcheck = mkOption {
      description = "HTTP endpoint that answers 2xx once the service is up; used by the image, compose and the parity test.";
      type = types.submodule {
        options = {
          port = mkOption {
            type = types.port;
            description = "Port to probe.";
          };
          path = mkOption {
            type = types.str;
            default = "/";
            description = "Path to probe.";
          };
          timeout = mkOption {
            type = types.ints.positive;
            default = 180;
            description = "Seconds the parity test waits for the first healthy answer.";
          };
        };
      };
    };

    dependencies = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Other services this one needs to run (e.g. \"postgresql\"). Informational for now.";
    };
  };
}
