# Idempotent single-node Garage cluster-layout bootstrap.
#
# Co-located with the apps.garage module; wrapped by writeShellApplication
# (adds the shebang + `set -euo pipefail`) and driven by the systemd oneshot
# `garage-layout-bootstrap.service`, which injects the parameters:
#
#   Environment=      GARAGE_ZONE, GARAGE_CAPACITY
#   EnvironmentFile=  the RPC-secret env file (GARAGE_RPC_SECRET)
#
# Logic mirrors fleetkit nix/modules/infra/data/s3 (INFRA-36 fixes): match the
# local node on a 16-char id prefix (layout show truncates ids), and apply
# current+1 so a re-assign after a capacity change still succeeds.

# Wait up to 60s for the daemon's RPC to answer after start.
for _ in $(seq 1 30); do
  if garage status >/dev/null 2>&1; then break; fi
  sleep 2
done

node_id="$(garage node id 2>/dev/null | awk -F'@' '{print $1}')"
if [ -z "$node_id" ]; then
  echo "garage-layout-bootstrap: 'garage node id' empty — daemon not ready" >&2
  exit 1
fi

if garage layout show 2>/dev/null | grep -q "${node_id:0:16}"; then
  echo "garage-layout-bootstrap: node ${node_id} already in layout — no-op"
  exit 0
fi

echo "garage-layout-bootstrap: assigning zone=${GARAGE_ZONE} capacity=${GARAGE_CAPACITY}"
garage layout assign -z "$GARAGE_ZONE" -c "$GARAGE_CAPACITY" "$node_id"

cur="$(garage layout show 2>/dev/null | awk '/[Cc]urrent cluster layout version/ {print $NF}')"
garage layout apply --version "$(( ${cur:-0} + 1 ))"
