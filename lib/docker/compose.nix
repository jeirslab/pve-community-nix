# A docker-compose snippet per service, generated from the contract so it
# can't drift from the image: the published image, every contract variable as
# `${VAR}` interpolation (Coolify and plain compose both fill these from
# their env UI / .env), ports, and a named volume per data directory.
{ lib, pkgs, registry }:

let
  volumeName = name: path:
    "${name}-${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" path)}";

  attrs = { name, c, volumes, tag ? "stable" }: {
    services.${name} = {
      image = "${registry}/${name}:${tag}";
      restart = "unless-stopped";
      environment = lib.mapAttrs
        (k: v:
          if v.default != null then "\${${k}:-${v.default}}"
          else if v.required then "\${${k}:?${k} is required}"
          else "\${${k}:-}")
        c.env;
      ports = map (p: "${toString p.port}:${toString p.port}${lib.optionalString (p.protocol == "udp") "/udp"}") c.ports;
      volumes = map (v: "${volumeName name v}:${v}") volumes;
    };
    volumes = lib.listToAttrs (map (v: lib.nameValuePair (volumeName name v) { }) volumes);
  };
in
{
  inherit attrs;

  file = { name, c, image, volumes }:
    pkgs.runCommand "${name}-compose.yaml"
      {
        nativeBuildInputs = [ pkgs.yq-go ];
        json = builtins.toJSON (attrs { inherit name c volumes; });
        passAsFile = [ "json" ];
      }
      ''
        yq -P -o yaml "$jsonPath" > $out
      '';
}
