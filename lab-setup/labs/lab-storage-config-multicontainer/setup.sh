#!/usr/bin/env bash
# setup.sh — prepares the themed lab "Storage · ConfigMap/Secrets · Sidecars".
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/setup.sh"
#
# Idempotent: first cleans up the previous state (namespaces + cluster-scoped PVs),
# then re-seeds the starting state. Contains NO solution.
set -uo pipefail

# Health gate: API/nodes/CNI + auto-repair of the expired Calico token (snapshot restore).
bash /vagrant/check-cluster-health.sh || exit 1

echo "🧹 Cleaning up the previous state (idempotent)…"
kubectl delete ns storage-lab config-lab multi-lab --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/storage-lab ns/config-lab ns/multi-lab --timeout=120s >/dev/null 2>&1 || true
# PVs are cluster-scoped: delete them explicitly (after the ns, so PVCs are already gone).
kubectl delete pv pv-data pv-archive --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete pv/pv-data pv/pv-archive --timeout=60s >/dev/null 2>&1 || true

kubectl create ns storage-lab >/dev/null 2>&1
kubectl create ns config-lab  >/dev/null 2>&1
kubectl create ns multi-lab   >/dev/null 2>&1

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN A — Storage
#   pv-data    (A2/A3) : static hostPath PV AVAILABLE, storageClassName=manual.
#   pv-archive (A4)    : static PV storageClassName=archive, left in RELEASED
#                        (bound then PVC deleted → stale claimRef, reclaimPolicy Retain).
echo "🌱 Seed A (Storage)…"
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-data
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/pv-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-archive
spec:
  capacity:
    storage: 3Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive
  hostPath:
    path: /mnt/pv-archive
    type: DirectoryOrCreate
EOF

# Bring pv-archive to the "Released" state: bind it to a temporary PVC, wait for the
# binding, then delete the PVC (Retain keeps a stale claimRef → Released).
kubectl -n storage-lab apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: old-claim
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: archive
  resources:
    requests:
      storage: 3Gi
EOF
for _ in $(seq 1 30); do
  [ "$(kubectl -n storage-lab get pvc old-claim -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && break
  sleep 1
done
kubectl -n storage-lab delete pvc old-claim --ignore-not-found >/dev/null 2>&1 || true
# pv-archive is now Released (stale claimRef kept by Retain).

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN B — ConfigMap & Secrets
#   Nothing to seed: the student creates app-config, db-credentials, web-index
#   and the api / web Pods themselves. The namespace is enough.
echo "🌱 Seed B (ConfigMap/Secrets)… (namespace ready, nothing to pre-create)"

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN C — Sidecars & multi-container
#   Nothing to seed: the student creates shared-logs (emptyDir) and web-agent (native sidecar).
echo "🌱 Seed C (multi-container)… (namespace ready, nothing to pre-create)"

echo
echo "✅ Storage/Config/Sidecars lab setup complete."
echo "   Starting state:"
kubectl get pv pv-data pv-archive -o custom-columns=PV:.metadata.name,CAPACITY:.spec.capacity.storage,SC:.spec.storageClassName,STATUS:.status.phase 2>/dev/null
echo "   Tasks: see LAB.md. Grade: bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"
