# The framework every service is built with. Services never import nixpkgs
# helpers for images, compose, checks or docs themselves — they declare a
# contract and a NixOS module, and this turns them into all the outputs.
{ nixpkgs, pkgs, registry, source }:

let
  inherit (nixpkgs) lib;

  mkService = import ./service.nix { inherit lib pkgs nixpkgs registry source; };

  # What a service's default.nix receives as `svc`.
  api = { inherit lib pkgs mkService; };

  # Proxmox VE host tooling — not services; see pve/default.nix.
  pve = import ./pve { inherit lib pkgs; };

  loadService = dir: import dir { svc = api; };

  loadServices = dir:
    let
      entries = builtins.readDir dir;
      names = lib.filter (n: entries.${n} == "directory") (lib.attrNames entries);
    in
    lib.listToAttrs (map
      (n:
        let s = loadService (dir + "/${n}"); in
        if s.name != n then throw "services/${n}: declares name \"${s.name}\"; the directory and the name must match"
        else lib.nameValuePair n s)
      names);
in
api // {
  inherit loadService loadServices pve;

  servicePackages = services: lib.concatMapAttrs
    (n: s: {
      "${n}-image" = s.image;
      "${n}-compose" = s.compose;
    })
    services;

  serviceChecks = services: lib.concatMapAttrs
    (n: s: {
      "${n}-eval" = s.checks.eval;
      "${n}-parity" = s.checks.parity;
    })
    services;

  docs = import ./docs.nix { inherit lib pkgs pve; };
}
