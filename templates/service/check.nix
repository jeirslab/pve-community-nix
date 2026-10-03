# Inputs for the parity test (lib/checks/parity.nix), which boots the
# NixOS module under systemd and the image under podman with the SAME env
# file and requires the contract healthcheck to pass on both.
{ pkgs, lib, ... }:

{
  # Test values; must cover every `required = true` variable. Never real secrets.
  env = {
    # EXAMPLE_VAR = "test-value";
  };

  # Extra NixOS config for the `native` test machine only (e.g. a database
  # the service depends on).
  nixos = { };

  # Extra Python test steps; machines are `native` and `container`.
  testScript = "";
}
