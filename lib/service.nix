# mkService: turn one service's declaration (services/<name>/default.nix)
# into everything the repo publishes for it — the NixOS module, the
# container image, the compose snippet, the checks and the docs inputs.
{ lib, pkgs, nixpkgs, registry, source }:

let
  contractModule = import ./contract.nix { inherit lib; };

  validate = name: contract:
    let
      c = (lib.evalModules { modules = [ contractModule { config = contract; } ]; }).config;
    in
    if c.approach == "extracted" && c.unit == null then
      throw "service ${name}: approach = \"extracted\" needs contract.unit (the systemd service to lift)"
    else if c.approach == "modular" && c.modularService == null then
      throw "service ${name}: approach = \"modular\" needs contract.modularService"
    else
      c;

  # A minimal NixOS system with just this service enabled — what both the
  # image backend and the eval check read.
  evalSystem = modules: nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      {
        boot.isContainer = true;
        networking.hostName = "svc";
        system.stateVersion = lib.trivial.release;
      }
    ] ++ modules;
  };

  extract = import ./docker/extract.nix { inherit lib pkgs registry source; };
  modular = import ./docker/modular.nix { inherit lib pkgs registry source; };
  compose = import ./docker/compose.nix { inherit lib pkgs registry; };
  parity = import ./checks/parity.nix { inherit lib pkgs; };
in

{ name
, contract
, module ? { }
, docker ? (_: { })
, check ? (_: { })
, upstream ? null
}:

let
  c = validate name contract;

  ports = proto: map (p: p.port) (lib.filter (p: p.protocol == proto) c.ports);

  # Contract defaults beat whatever the wrapped nixpkgs module sets (normal
  # priority) but still lose to an explicit mkForce in configuration.nix.
  contractPriority = lib.mkOverride 75;

  # The part of every service's NixOS module that is the same everywhere.
  baseModule = { config, ... }:
    let cfg = config.svc.${name}; in
    {
      options.svc.${name} = {
        enable = lib.mkEnableOption c.description;
        environmentFile = lib.mkOption {
          type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
          default = null;
          description = ''
            File of `KEY=value` lines (systemd EnvironmentFile). Takes the same
            variables as the container image; see the service's environment
            table. Values here override the contract defaults.
          '';
        };
        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open the service's ports in the NixOS firewall.";
        };
      };

      config = lib.mkIf cfg.enable (lib.mkMerge [
        (lib.mkIf (c.approach == "extracted") {
          systemd.services.${c.unit} = {
            environment = lib.mapAttrs (_: v: contractPriority v.default)
              (lib.filterAttrs (_: v: v.default != null) c.env);
            serviceConfig.EnvironmentFile =
              lib.mkIf (cfg.environmentFile != null) [ (toString cfg.environmentFile) ];
          };
        })
        (lib.mkIf cfg.openFirewall {
          networking.firewall.allowedTCPPorts = ports "tcp";
          networking.firewall.allowedUDPPorts = ports "udp";
        })
      ]);
    };

  fullModule = {
    _file = "services/${name}";
    imports = [ baseModule module ];
  };

  system = evalSystem [ fullModule { svc.${name}.enable = true; } ];

  dockerCfg = {
    volumes = [ ];
    contents = [ ];
    user = "1000:1000";
  } // docker { inherit pkgs lib; };

  checkCfg = {
    env = { };
    nixos = { };
    testScript = "";
  } // check { inherit pkgs lib; };

  image = (if c.approach == "extracted" then extract else modular) {
    inherit name c system dockerCfg;
  };

  # The env file both sides of the parity test start with: check.nix's test
  # values, which must cover every required variable.
  missingTestEnv = lib.filter (k: c.env.${k}.required && !(checkCfg.env ? ${k})) (lib.attrNames c.env);
  envFile =
    if missingTestEnv != [ ] then
      throw "service ${name}: check.nix must set test values for required env vars: ${toString missingTestEnv}"
    else
      pkgs.writeText "${name}-test.env"
        (lib.concatStrings (lib.mapAttrsToList (k: v: "${k}=${v}\n") checkCfg.env));
in
{
  inherit name upstream system image;
  contract = c;
  module = fullModule;
  docker = dockerCfg;
  compose = compose.file { inherit name c image; inherit (image.passthru) volumes; };
  composeAttrs = compose.attrs { inherit name c; inherit (image.passthru) volumes; };
  checks = {
    # Forces evaluation of the whole NixOS system (instantiates, builds nothing).
    eval = pkgs.runCommand "${name}-eval" { } ''
      echo ${system.config.system.build.toplevel.drvPath} > $out
    '';
    parity = parity { inherit name c fullModule image envFile checkCfg; };
  };
}
