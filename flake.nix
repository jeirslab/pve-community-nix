{
  description = "NixOS service modules, each with a container image that runs the same service and a test that proves the two match";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      svc = import ./lib {
        inherit nixpkgs pkgs;
        # Where images are pushed; also baked into each generated compose file.
        registry = "ghcr.io/jeirslab/svc";
        source = "https://github.com/jeirslab/pve-community-nix";
      };
      # Every directory under services/ is one service (see templates/service).
      services = svc.loadServices ./services;
      fixture = svc.loadService ./lib/tests/fixture;
    in
    {
      lib = svc;

      nixosModules = builtins.mapAttrs (_: s: s.module) services // {
        default = { imports = map (s: s.module) (builtins.attrValues services); };
      };

      packages.${system} =
        svc.servicePackages services
        // {
          docs = svc.docs services;
          fixture-image = fixture.image;
        };

      checks.${system} =
        svc.serviceChecks services
        # The framework's own proof: a tiny built-in service run both ways.
        // {
          framework-fixture-eval = fixture.checks.eval;
          framework-fixture-parity = fixture.checks.parity;
          framework-docs = svc.docs services;
        };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
