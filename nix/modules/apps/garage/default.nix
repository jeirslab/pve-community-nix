{ config, lib, pkgs, ... }:

# apps.garage — tier 1 (nixos-service): wraps upstream services.garage as a
# reusable catalog template for an S3-compatible object store (the NixOS
# equivalent of the legacy legacy/ct/garage.sh LXC).
#
# The legacy garage-install.sh downloaded a static binary, wrote /etc/garage.toml
# with generated RPC/admin tokens, and left layout/bucket/key setup to the
# operator. Here NixOS owns the service + config, and the imperative bring-up
# that Garage cannot express declaratively lives in CO-LOCATED shell scripts
# (layout-bootstrap.sh / buckets-bootstrap.sh / key-bootstrap.sh) run as
# idempotent systemd oneshots — no Ansible. All three re-run cleanly on every
# boot, so `colmena apply` (or a reboot) is the whole deployment.
#
# Operational lessons baked in (from Skrybit's s3 host, INFRA-246/256): pin a
# static `garage` user (the upstream module's DynamicUser can't own a data-dir
# on a block-device mount), hard-require the data mount so Garage never comes
# up against an empty shadow dir, and reserve headroom on the data filesystem
# for the unprivileged uid (left to the host — see the consumer).

let
  cfg = config.apps.garage;
  preset = config.fleet.catalog.apps.garage;

  layoutScript = pkgs.writeShellApplication {
    name = "garage-layout-bootstrap";
    runtimeInputs = [ cfg.package pkgs.gawk pkgs.gnugrep pkgs.coreutils ];
    text = builtins.readFile ./layout-bootstrap.sh;
  };
  bucketsScript = pkgs.writeShellApplication {
    name = "garage-buckets-bootstrap";
    runtimeInputs = [ cfg.package pkgs.gnugrep pkgs.coreutils ];
    text = builtins.readFile ./buckets-bootstrap.sh;
  };
  keyScript = pkgs.writeShellApplication {
    name = "garage-key-bootstrap";
    runtimeInputs = [ cfg.package pkgs.gnugrep pkgs.coreutils ];
    text = builtins.readFile ./key-bootstrap.sh;
  };

  # Common ordering: every bootstrap oneshot runs after garage is up, and keys
  # run after layout + buckets so grants land on buckets that exist.
  afterGarage = [ "garage.service" "network-online.target" ];

  grantsFor = k: lib.concatMapStringsSep "\n"
    (g: "${g.bucket} ${lib.optionalString g.read "r"}${lib.optionalString g.write "w"}${lib.optionalString g.owner "o"}")
    k.allow;
in
{
  options.apps.garage = {
    enable = lib.mkEnableOption "Garage S3-compatible object store (catalog app)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.garage_1;
      defaultText = lib.literalExpression "pkgs.garage_1";
      description = "Garage package. Pin the major (garage_1) so a channel bump can't silently change the on-disk format.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/garage";
      description = "Root of the Garage state tree (meta/ + data/ live here). Point this at the mountpoint of the dedicated data volume; the module hard-requires the mount.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/garage-env";
      defaultText = lib.literalExpression ''"/run/secrets/garage-env"'';
      example = lib.literalExpression ''config.sops.templates."garage.env".path'';
      description = ''
        Env file carrying GARAGE_RPC_SECRET (also read by the bootstrap
        oneshots). The default is a placeholder — a real deployment MUST point
        this at the rendered secret (almost always the same
        sops.templates."<name>".path passed to services.garage.environmentFile),
        or Garage will fail to start with no RPC secret.
      '';
    };

    replicationFactor = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Garage replication factor. 1 = single-node store.";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "garage";
      description = "S3 region advertised by the API (clients must sign with the same value).";
    };

    rootDomain = lib.mkOption {
      type = lib.types.str;
      default = ".s3.local";
      example = ".s3.jeirs.lan";
      description = "S3 API vhost root domain (bucket.<rootDomain> path-style suffix). Set to the fleet's internal S3 domain.";
    };

    rpcPublicAddr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.0.0.10:3901";
      description = "RPC address other Garage nodes reach this one on. null on a single-node store.";
    };

    web = {
      enable = lib.mkEnableOption "the Garage static-website S3 endpoint (s3_web)";
      rootDomain = lib.mkOption {
        type = lib.types.str;
        default = ".web.local";
        example = ".web.jeirs.lan";
        description = "Root domain for the static-website endpoint.";
      };
    };

    layout = lib.mkOption {
      default = null;
      description = "Single-node layout to assign on first boot (idempotent). null on a multi-node cluster where the operator owns layout out of band.";
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          zone = lib.mkOption { type = lib.types.str; default = "dc1"; description = "Garage zone label."; };
          capacity = lib.mkOption { type = lib.types.str; example = "9T"; description = "Advertised node capacity (Garage units, e.g. \"9T\"); match the data volume size."; };
        };
      });
    };

    buckets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "pbs-chunkstore" "ai-models" ];
      description = "Bucket names to ensure exist (idempotent).";
    };

    keys = lib.mkOption {
      default = [ ];
      description = ''
        Declared access keys to import and grant. Each key's credentials are
        supplied out of band (SOPS) via credentialsFile so producer and
        consumer share one credential — Garage never generates them here.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; description = "Garage key name (label)."; };
          credentialsFile = lib.mkOption {
            type = lib.types.path;
            description = "Env file providing GARAGE_KEY_ACCESS_KEY_ID and GARAGE_KEY_SECRET_ACCESS_KEY (a SOPS template).";
          };
          allow = lib.mkOption {
            default = [ ];
            description = "Bucket grants for this key.";
            type = lib.types.listOf (lib.types.submodule {
              options = {
                bucket = lib.mkOption { type = lib.types.str; description = "Bucket name."; };
                read = lib.mkOption { type = lib.types.bool; default = true; description = "Grant read."; };
                write = lib.mkOption { type = lib.types.bool; default = true; description = "Grant write."; };
                owner = lib.mkOption { type = lib.types.bool; default = false; description = "Grant owner (bucket admin: create/delete keys' access, website, etc.)."; };
              };
            });
          };
        };
      });
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra attrs merged into services.garage.settings (escape hatch for keys this module does not surface).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.apps.base.port == preset.port;
      message = "apps.garage: apps.base.port must stay ${toString preset.port} (Garage's S3 API port).";
    }];

    # Static user owning the data mount (upstream DynamicUser can't).
    users.groups.garage = { };
    users.users.garage = {
      isSystemUser = true;
      group = "garage";
      home = cfg.dataDir;
    };

    services.garage = {
      enable = true;
      package = cfg.package;
      environmentFile = cfg.environmentFile;
      settings = lib.recursiveUpdate {
        replication_factor = cfg.replicationFactor;
        rpc_bind_addr = "[::]:3901";
        metadata_dir = "${cfg.dataDir}/meta";
        data_dir = "${cfg.dataDir}/data";
        db_engine = "lmdb";
        s3_api = {
          api_bind_addr = "[::]:3900";
          s3_region = cfg.region;
          root_domain = cfg.rootDomain;
        };
        admin.api_bind_addr = "127.0.0.1:3903";
      } (lib.optionalAttrs (cfg.rpcPublicAddr != null) {
        rpc_public_addr = cfg.rpcPublicAddr;
      } // lib.optionalAttrs cfg.web.enable {
        s3_web = {
          bind_addr = "[::]:3902";
          root_domain = cfg.web.rootDomain;
          index = "index.html";
        };
      } // cfg.extraSettings);
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 garage garage -"
      "d ${cfg.dataDir}/meta 0700 garage garage -"
      "d ${cfg.dataDir}/data 0700 garage garage -"
    ];

    systemd.services = lib.mkMerge [
      # Pin the service to the static user + hard-require the data mount so
      # Garage never initialises an empty shadow DB on the root fs.
      {
        garage.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = lib.mkForce "garage";
          Group = lib.mkForce "garage";
        };
        garage.unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      }

      (lib.mkIf (cfg.layout != null) {
        garage-layout-bootstrap = {
          description = "Assign + apply Garage cluster layout for the local node";
          after = afterGarage;
          requires = [ "garage.service" ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            GARAGE_ZONE = cfg.layout.zone;
            GARAGE_CAPACITY = cfg.layout.capacity;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            EnvironmentFile = [ cfg.environmentFile ];
            ExecStart = lib.getExe layoutScript;
          };
        };
      })

      (lib.mkIf (cfg.buckets != [ ]) {
        garage-buckets-bootstrap = {
          description = "Ensure declared Garage buckets exist (idempotent)";
          after = afterGarage ++ lib.optional (cfg.layout != null) "garage-layout-bootstrap.service";
          requires = [ "garage.service" ] ++ lib.optional (cfg.layout != null) "garage-layout-bootstrap.service";
          wantedBy = [ "multi-user.target" ];
          environment.GARAGE_BUCKETS = lib.concatStringsSep " " cfg.buckets;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            EnvironmentFile = [ cfg.environmentFile ];
            ExecStart = lib.getExe bucketsScript;
          };
        };
      })

      # One oneshot per declared key (each with its own credentials file).
      (lib.listToAttrs (map
        (k: lib.nameValuePair "garage-key-${k.name}-bootstrap" {
          description = "Import Garage key '${k.name}' and grant its buckets (idempotent)";
          after = afterGarage
            ++ lib.optional (cfg.layout != null) "garage-layout-bootstrap.service"
            ++ lib.optional (cfg.buckets != [ ]) "garage-buckets-bootstrap.service";
          requires = [ "garage.service" ]
            ++ lib.optional (cfg.buckets != [ ]) "garage-buckets-bootstrap.service";
          wantedBy = [ "multi-user.target" ];
          environment = {
            GARAGE_KEY_NAME = k.name;
            GARAGE_KEY_GRANTS = grantsFor k;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            EnvironmentFile = [ cfg.environmentFile k.credentialsFile ];
            ExecStart = lib.getExe keyScript;
          };
        })
        cfg.keys))
    ];
  };
}
