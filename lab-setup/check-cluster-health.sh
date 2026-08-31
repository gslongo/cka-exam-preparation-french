#!/usr/bin/env bash
# check-cluster-health.sh — health gate run by every lab/exam setup.sh before seeding.
# Run ON cp1 (sourced path: /vagrant/check-cluster-health.sh).
#
# Catches the classic "snapshot restore" failure mode: the Calico CNI token has
# expired and every NEW Pod hangs in ContainerCreating with
#   plugin type="calico" failed (add): … connection is unauthorized: Unauthorized
# In that case it auto-remediates (rollout restart of Calico) and re-checks.
# Checks: (1) API server ready, (2) all nodes Ready, (3) a new Pod actually
# gets a sandbox + becomes Ready (real CNI smoke test).
set -uo pipefail

SMOKE_NS=default
SMOKE_POD="cni-smoke-$$"
# Use the node's own sandbox image: guaranteed present, no pull needed.
PAUSE_IMG=$(sudo crictl info 2>/dev/null | grep -oP '"sandboxImage": "\K[^"]+' || true)
[ -n "${PAUSE_IMG:-}" ] || PAUSE_IMG=registry.k8s.io/pause:3.10

cleanup() { kubectl -n "$SMOKE_NS" delete pod "$SMOKE_POD" --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "❌ Cluster health check failed: $1" >&2; exit 1; }

echo "🩺 Cluster health check…"

# 1) API server — allow up to 60 s (VMs may still be booting after a snapshot restore).
echo "  [1/3] API server… (up to 60 s)"
API_OK=""
for _ in $(seq 1 12); do
  kubectl get --raw /readyz >/dev/null 2>&1 && { API_OK=1; break; }
  echo "        ⏳ API not ready yet — retrying in 5 s…"
  sleep 5
done
[ -n "$API_OK" ] || fail "API server not ready after 60 s (kubectl get --raw /readyz)."
echo "        ✔ API server ready"

# 2) Nodes — wait for Ready (kubelets report back one by one after a restore).
#    The Ready condition is independent from cordon (SchedulingDisabled is fine).
echo "  [2/3] Nodes Ready… (up to 180 s — kubelet heartbeats can lag after a snapshot restore)"
kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null 2>&1 \
  || fail "node(s) still not Ready after 180 s: $(kubectl get nodes --no-headers | awk '$2 !~ /^Ready/ {print $1}' | tr '\n' ' ')"
echo "        ✔ all nodes Ready"

# 3) CNI smoke test — can a brand-new Pod get a network sandbox?
echo "  [3/3] CNI smoke test… (ephemeral pause Pod, up to 90 s)"
smoke() {
  cleanup
  kubectl -n "$SMOKE_NS" apply -f - <<EOF >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $SMOKE_POD
spec:
  terminationGracePeriodSeconds: 0
  tolerations:
  - operator: Exists
  containers:
  - name: pause
    image: $PAUSE_IMG
EOF
  kubectl -n "$SMOKE_NS" wait pod "$SMOKE_POD" --for=condition=Ready --timeout=90s >/dev/null 2>&1
}

if ! smoke; then
  EVENTS=$(kubectl -n "$SMOKE_NS" describe pod "$SMOKE_POD" 2>/dev/null | sed -n '/^Events:/,$p')
  if echo "$EVENTS" | grep -qi 'unauthorized'; then
    echo "        ⚠️  Calico CNI token expired (typical after a snapshot restore) — restarting Calico… (up to 240 s)"
    kubectl -n calico-system rollout restart ds/calico-node deploy/calico-kube-controllers >/dev/null 2>&1 \
      || fail "could not restart Calico (namespace calico-system)."
    kubectl -n calico-system rollout status ds/calico-node --timeout=240s >/dev/null 2>&1 \
      || fail "calico-node did not come back after the restart."
    echo "        ⏳ Calico restarted — re-running the smoke test…"
    smoke || fail "CNI still broken after the Calico restart — investigate manually (kubectl describe pod)."
    echo "        ✔ Calico repaired — new Pods get their sandbox again"
  else
    fail "a new Pod does not become Ready (cause other than the Calico token). Last events:
$EVENTS"
  fi
fi
echo "        ✔ CNI OK (sandbox + Pod Ready)"

echo "✅ Cluster healthy (API, nodes, CNI)."
