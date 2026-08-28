#!/usr/bin/env bash
# setup.sh — prépare le lab thématique « Stockage · ConfigMap/Secrets · Sidecars ».
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/setup.sh"
#
# Idempotent : nettoie d'abord l'état précédent (namespaces + PV cluster-scoped),
# puis re-sème l'état de départ. NE contient AUCUNE solution.
set -uo pipefail

echo "🧹 Nettoyage de l'état précédent (idempotent)…"
kubectl delete ns storage-lab config-lab multi-lab --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/storage-lab ns/config-lab ns/multi-lab --timeout=120s >/dev/null 2>&1 || true
# Les PV sont cluster-scoped : les supprimer explicitement (après les ns, donc PVC déjà partis).
kubectl delete pv pv-data pv-archive --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete pv/pv-data pv/pv-archive --timeout=60s >/dev/null 2>&1 || true

kubectl create ns storage-lab >/dev/null 2>&1
kubectl create ns config-lab  >/dev/null 2>&1
kubectl create ns multi-lab   >/dev/null 2>&1

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE A — Stockage
#   pv-data    (A2/A3) : PV statique hostPath DISPONIBLE, storageClassName=manual.
#   pv-archive (A4)    : PV statique storageClassName=archive, laissé en RELEASED
#                        (lié puis PVC supprimé → claimRef périmé, reclaimPolicy Retain).
echo "🌱 Seed A (Stockage)…"
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

# Amener pv-archive en état "Released" : le lier à un PVC temporaire, attendre le
# binding, puis supprimer le PVC (Retain conserve un claimRef périmé → Released).
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
# pv-archive est maintenant en Released (claimRef périmé conservé par Retain).

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE B — ConfigMap & Secrets
#   Rien à semer : l'étudiant crée lui-même app-config, db-credentials, web-index
#   et les Pods api / web. Le namespace suffit.
echo "🌱 Seed B (ConfigMap/Secrets)… (namespace prêt, rien à pré-créer)"

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE C — Sidecars & multi-conteneurs
#   Rien à semer : l'étudiant crée shared-logs (emptyDir) et web-agent (sidecar natif).
echo "🌱 Seed C (multi-conteneurs)… (namespace prêt, rien à pré-créer)"

echo
echo "✅ Setup lab Stockage/Config/Sidecars terminé."
echo "   État de départ :"
kubectl get pv pv-data pv-archive -o custom-columns=PV:.metadata.name,CAPACITY:.spec.capacity.storage,SC:.spec.storageClassName,STATUS:.status.phase 2>/dev/null
echo "   Tâches : voir LAB.md. Correction : bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"
