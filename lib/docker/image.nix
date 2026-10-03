# The image wrapper both approaches share: a non-root user, CA certs, /bin/sh,
# the contract's ports, volumes, healthcheck and OCI labels around whatever
# entrypoint the approach produced.
{ lib, pkgs, registry, source }:

{ name, c, dockerCfg, entrypoint, dirs ? [ ], volumes ? [ ], workingDir ? "/", tag ? "latest" }:

let
  allVolumes = lib.unique (volumes ++ map (v: v.path) dockerCfg.volumes);
  owned = lib.unique (dirs ++ allVolumes);

  # One non-root user for every image; systemd's DynamicUser has no
  # container equivalent.
  nss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = [ "svc:x:1000:1000:service:/var/empty:/bin/sh" ];
    extraGroupLines = [ "svc:x:1000:" ];
  };

  seconds = s: s * 1000000000;
in
(pkgs.dockerTools.buildLayeredImage {
  name = "${registry}/${name}";
  inherit tag;
  contents = [ nss pkgs.dockerTools.caCertificates pkgs.dockerTools.binSh ] ++ dockerCfg.contents;
  enableFakechroot = false;
  fakeRootCommands = ''
    mkdir -p tmp ${lib.concatMapStringsSep " " (d: "." + d) owned}
    chmod 1777 tmp
    ${lib.optionalString (owned != [ ]) "chown -R 1000:1000 ${lib.concatMapStringsSep " " (d: "." + d) owned}"}
  '';
  config = {
    Entrypoint = [ "${entrypoint}" ];
    User = dockerCfg.user;
    WorkingDir = workingDir;
    ExposedPorts = lib.listToAttrs (map (p: lib.nameValuePair "${toString p.port}/${p.protocol}" { }) c.ports);
    Volumes = lib.listToAttrs (map (v: lib.nameValuePair v { }) allVolumes);
    Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
    Healthcheck = {
      Test = [ "CMD" "${pkgs.curl}/bin/curl" "-fsS" "-o" "/dev/null"
        "http://127.0.0.1:${toString c.healthcheck.port}${c.healthcheck.path}" ];
      Interval = seconds 30;
      Timeout = seconds 10;
      StartPeriod = seconds c.healthcheck.timeout;
      Retries = 3;
    };
    Labels = {
      "org.opencontainers.image.title" = name;
      "org.opencontainers.image.description" = c.description;
      "org.opencontainers.image.source" = source;
    } // lib.optionalAttrs (c.homepage != null) { "org.opencontainers.image.url" = c.homepage; };
  };
}).overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit entrypoint;
    volumes = allVolumes;
    ref = "${registry}/${name}:${tag}";
  };
})
