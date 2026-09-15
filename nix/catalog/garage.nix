{ ... }:

# Curated overrides for the Garage preset (plain values beat the mkDefaults in
# generated/garage.nix). Garage is a NixOS-service app implemented by
# nix/modules/apps/garage — a reusable S3 object-store template.
{
  fleet.catalog.apps.garage = {
    title = "Garage";
    description = "S3-compatible distributed object storage";
    category = "object-storage";
    tags = [ "s3" "storage" ];
    upstream = {
      url = "https://garagehq.deuxfleurs.fr/";
      repo = "deuxfleurs-org/garage";
      repoHost = "other"; # git.deuxfleurs.fr (mirrored to GitHub)
      license = "AGPL-3.0";
    };

    # S3 API is the primary port; the static-website endpoint is opened too.
    # Admin (3903) binds localhost; RPC (3901) is inter-node only.
    port = 3900;
    extraPorts = [ 3902 ];

    # Garage itself is light — the object data lives on a dedicated mount, not
    # the root disk. Consumers size the data volume via mkApp mount_points.
    defaults = { cpu_cores = 2; memory_mb = 1024; root_disk_gb = 8; };

    kind = "container";
    privileged = false;
    arch = [ "x86_64" "aarch64" ];

    impl = "nixos-service";
    nixModule = "garage";
    status = "ported";
  };
}
