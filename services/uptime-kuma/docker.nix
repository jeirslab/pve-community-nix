# Container-only needs. The image already gets the unit's StateDirectory as
# a volume, a non-root user (uid 1000), CA certs and /bin/sh. Add here only
# what the container needs on top.
{ pkgs, lib, ... }:

{
  # Extra persistent paths (beyond the unit's StateDirectory):
  volumes = [
    # { path = "/var/lib/uptime-kuma/uploads"; description = "Uploaded files"; }
  ];

  # Extra packages in the image (rarely needed; the unit's closure is already in):
  contents = [ ];

  # user = "1000:1000";
}
