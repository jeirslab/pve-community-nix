# Using a service

Every service is configured only through environment variables. Each
service's page lists them with their defaults.

## Docker / Coolify

Copy the service's compose snippet. Every variable is written as
`${VAR}` / `${VAR:-default}`, so set them in Coolify's environment UI or a
`.env` file next to the compose file. Data lives in the named volumes the
snippet declares.

Tags: `:stable` (released), `:edge` (latest nightly build), `:<release>`.

## NixOS

```nix
{
  inputs.pve-community-nix.url = "github:jeirslab/pve-community-nix/stable";

  # in a host's configuration:
  imports = [ inputs.pve-community-nix.nixosModules.<name> ];
  svc.<name> = {
    enable = true;
    environmentFile = "/run/secrets/<name>.env";   # e.g. rendered by sops-nix
    openFirewall = true;
  };
}
```

The `environmentFile` takes exactly the variables the image takes.
