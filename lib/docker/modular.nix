# The `modular` approach: the service is a nixpkgs modular service
# (`system.services.<name>`), whose process definition is already
# independent of systemd — the image runs its argv directly. NixOS turns the
# same definition into a systemd unit on hosts, so there is nothing to
# extract. Modular services are still marked experimental in nixpkgs; the
# modular-watch automation re-checks `extracted` services as support grows.
{ lib, pkgs, registry, source }:

{ name, c, system, dockerCfg, tag ? "latest" }:

let
  mkImage = import ./image.nix { inherit lib pkgs registry source; };

  ms = system.config.system.services.${c.modularService}
    or (throw "service ${name}: no system.services.${c.modularService} in the evaluated system — check contract.modularService");

  # Same rule as `extracted`: contract defaults, overridable at runtime.
  defaults = lib.mapAttrs (_: v: v.default) (lib.filterAttrs (_: v: v.default != null) c.env);

  entrypoint = pkgs.writeShellScript "${name}-entrypoint" ''
    set -eu
    ${lib.concatStrings (lib.mapAttrsToList (k: v: ''
      if [ -z "''${${k}+set}" ]; then export ${k}=${lib.escapeShellArg v}; fi
    '') defaults)}
    exec ${lib.escapeShellArgs ms.process.argv}
  '';
in
mkImage {
  inherit name c dockerCfg entrypoint tag;
}
