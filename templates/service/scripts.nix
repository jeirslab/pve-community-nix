# Setup the service needs that isn't plain configuration: first-run
# initialisation, migrations, generating a config file from env vars.
# Hook it into the unit's preStart so it runs on NixOS AND in the container
# (the `extracted` image runs the unit's preStart before ExecStart). Scripts
# run as the service user and must be idempotent.
{ config, lib, pkgs, ... }:

let
  cfg = config.svc.__NAME__;
in
{
  config = lib.mkIf cfg.enable {
    # systemd.services.__NAME__.preStart = ''
    #   ...
    # '';
  };
}
