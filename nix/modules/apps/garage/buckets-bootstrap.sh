# Ensure the declared Garage buckets exist (idempotent).
#
# Co-located with the apps.garage module; wrapped by writeShellApplication and
# driven by `garage-buckets-bootstrap.service`, which injects:
#
#   Environment=      GARAGE_BUCKETS (space-separated bucket names)
#   EnvironmentFile=  the RPC-secret env file (GARAGE_RPC_SECRET)
#
# `bucket info` is the existence probe, so re-running on every boot is a no-op.

# Wait for the cluster to report a live node — bucket ops against a
# layout-less cluster fail with a noisy error we'd rather skip.
for _ in $(seq 1 30); do
  if garage status 2>/dev/null | grep -qE "HEALTHY|UP"; then break; fi
  sleep 2
done

read -ra buckets <<< "${GARAGE_BUCKETS:-}"
for b in "${buckets[@]}"; do
  [ -n "$b" ] || continue
  if garage bucket info "$b" >/dev/null 2>&1; then
    echo "garage-buckets-bootstrap: ${b}: exists"
  else
    echo "garage-buckets-bootstrap: ${b}: creating"
    garage bucket create "$b"
  fi
done
