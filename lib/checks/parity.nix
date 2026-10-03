# The parity test: one NixOS VM test, two machines. `native` runs the
# service from its NixOS module under systemd; `container` runs the built
# image under podman. Both get the same env file and must pass the same
# healthcheck. This is what "develop in Docker, deploy on NixOS" rests on.
{ lib, pkgs }:

{ name, c, fullModule, image, envFile, checkCfg }:

let
  url = "http://127.0.0.1:${toString c.healthcheck.port}${c.healthcheck.path}";
  timeout = toString c.healthcheck.timeout;
in
pkgs.testers.runNixOSTest {
  name = "${name}-parity";

  nodes.native = {
    imports = [ fullModule checkCfg.nixos ];
    svc.${name} = {
      enable = true;
      environmentFile = envFile;
    };
    virtualisation.memorySize = 2048;
    environment.systemPackages = [ pkgs.curl ];
  };

  nodes.container = {
    virtualisation.podman.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 8192;
    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = ''
    start_all()

    with subtest("native: the NixOS module under systemd"):
        native.wait_for_unit("multi-user.target")
        native.wait_until_succeeds("curl -fsS -o /dev/null ${url}", timeout=${timeout})

    with subtest("container: the image under podman, same env"):
        container.wait_for_unit("multi-user.target")
        container.succeed("podman load -i ${image}")
        container.succeed(
            "podman run -d --name ${name} --network host --env-file ${envFile} ${image.passthru.ref}"
        )
        try:
            container.wait_until_succeeds("curl -fsS -o /dev/null ${url}", timeout=${timeout})
        finally:
            # On failure this is the only view into why the container didn't come up.
            print(container.execute("podman ps -a; podman logs ${name} 2>&1 | tail -40")[1])

    ${checkCfg.testScript}
  '';
}
