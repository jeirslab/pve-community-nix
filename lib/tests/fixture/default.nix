# Framework self-test, not a real service: a busybox httpd that exercises
# everything the `extracted` approach has to carry from systemd into a
# container — a pre-start script, a StateDirectory, DynamicUser, an env var
# with a contract default, a required env var, and ${VAR} expansion in
# ExecStart. Its parity check runs in `nix flake check` as
# framework-fixture-parity.
{ svc }:

svc.mkService {
  name = "fixture";

  contract = {
    description = "Framework self-test: a tiny static HTTP server.";
    approach = "extracted";
    unit = "fixture";
    ports = [ { port = 8080; description = "HTTP"; } ];
    env = {
      FIXTURE_PORT = {
        description = "Port to listen on.";
        default = "8080";
      };
      FIXTURE_GREETING = {
        description = "Text served at /.";
        required = true;
        example = "hello";
      };
    };
    healthcheck = {
      port = 8080;
      path = "/";
      timeout = 60;
    };
  };

  module = { pkgs, ... }: {
    systemd.services.fixture = {
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.coreutils ];
      preStart = ''
        mkdir -p "$STATE_DIRECTORY/www"
        printf '%s\n' "$FIXTURE_GREETING" > "$STATE_DIRECTORY/www/index.html"
      '';
      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "fixture";
        ExecStart = "${pkgs.busybox}/bin/httpd -f -p \${FIXTURE_PORT} -h /var/lib/fixture/www";
      };
    };
  };

  check = _: {
    env.FIXTURE_GREETING = "hello from the parity test";
    testScript = ''
      with subtest("both serve the configured greeting"):
          for m in (native, container):
              m.succeed("curl -fsS http://127.0.0.1:8080/ | grep -q 'hello from the parity test'")
    '';
  };
}
