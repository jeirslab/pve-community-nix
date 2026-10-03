# The NixOS side. Prefer enabling and configuring the existing nixpkgs
# module over writing a systemd service by hand. Configuration the user
# controls must arrive as env vars (the contract) — set defaults in the
# contract, not here, so they apply to the container identically. Bind to
# 0.0.0.0 (via a contract default) so the container is reachable.
{ config, lib, pkgs, ... }:

let
  cfg = config.svc.uptime-kuma;
in
{
  config = lib.mkIf cfg.enable {
    services.uptime-kuma.enable = true;
  };
}
