#!/usr/bin/env bash
# setup.sh — prepare the "Cluster Maintenance, etcd & Security" lab (CKA domain 01).
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-cluster-maintenance/setup.sh"
#
# This is an OPERATIONAL lab: you perform real cluster-admin operations (etcd backup,
# CSR approval, RBAC, node drain, static pods). setup.sh only seeds the prerequisites;
# YOU do the work (see LAB.md). Idempotent: it first undoes any previous run (including
# a graded/solved state) and then re-seeds the initial state. It contains NO solutions.
set -uo pipefail

GOOD_IMG="nginx:1.29-alpine"
NSES="finance legacy"
STATIC_MANIFEST="/etc/kubernetes/manifests/web-static.yaml"
BACKUP="/var/lib/etcd/etcd-backup.db"
RESTORE_DIR="/var/lib/etcd/restore"
REPORT_DIR="/opt/cka"

echo "🧹 Cleaning up previous state (idempotent)…"

# 1) Node maintenance leftovers: bring w1 back, drop lab taint/label.
kubectl uncordon w1 >/dev/null 2>&1 || true
kubectl taint node w1 dedicated- maintenance- >/dev/null 2>&1 || true
kubectl label node w1 tier- >/dev/null 2>&1 || true

# 2) Static pod dropped on cp1 by a previous solution.
sudo rm -f "$STATIC_MANIFEST" 2>/dev/null || true

# 3) etcd artefacts produced by a previous backup/restore.
sudo rm -f "$BACKUP" 2>/dev/null || true
sudo rm -rf "$RESTORE_DIR" 2>/dev/null || true

# 4) Cluster-scoped objects + namespaces from a previous run.
kubectl delete csr applicant --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrole pod-viewer --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrolebinding pod-viewer-binding --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns $NSES --ignore-not-found >/dev/null 2>&1 || true
for ns in $NSES; do kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true; done
sudo rm -rf "$REPORT_DIR" 2>/dev/null || true

echo "🌱 Seeding namespaces…"
for ns in $NSES; do
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns unavailable (Terminating?)"; break; }
    sleep 2
  done
done

# ── T3 — a client CertificateSigningRequest is PENDING and must be approved ──────
echo "🌱 Task 3 (pending CSR 'applicant')…"
openssl genrsa -out /tmp/applicant.key 2048 >/dev/null 2>&1
openssl req -new -key /tmp/applicant.key -subj "/CN=applicant/O=examgroup" -out /tmp/applicant.csr >/dev/null 2>&1
REQ=$(base64 -w0 < /tmp/applicant.csr)
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: applicant
spec:
  request: ${REQ}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF

# ── T7 — a workload pinned to w1 that must be evacuated by 'drain' ───────────────
echo "🌱 Task 7 (workload 'legacy-app' pinned to w1)…"
kubectl label node w1 tier=legacy --overwrite >/dev/null 2>&1
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
  namespace: legacy
spec:
  replicas: 2
  selector: { matchLabels: { app: legacy-app } }
  template:
    metadata: { labels: { app: legacy-app } }
    spec:
      nodeSelector: { tier: legacy }
      containers:
      - name: web
        image: ${GOOD_IMG}
        ports: [{ containerPort: 80 }]
EOF

# ── T6 — a writable directory for the certificate-expiration report ──────────────
sudo mkdir -p "$REPORT_DIR" && sudo chmod 1777 "$REPORT_DIR"

rm -f /tmp/applicant.key /tmp/applicant.csr 2>/dev/null || true

echo ""
echo "✅ Cluster-maintenance lab ready — perform the 8 tasks, then grade yourself."
echo "   • Tasks   : lab-setup/labs/lab-cluster-maintenance/LAB.md"
echo "   • Grade   : bash /vagrant/labs/lab-cluster-maintenance/grade.sh"
echo "   • Nodes   :"
kubectl get nodes -o wide 2>/dev/null | awk 'NR==1{printf "     %-6s %-9s %s\n",$1,$2,"ROLES"} NR>1{printf "     %-6s %-9s %s\n",$1,$2,$3}'
