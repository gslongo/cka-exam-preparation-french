#!/usr/bin/env bash
# setup.sh — prepares the CKA mock-exam environment on the lab cluster.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"
#
# Idempotent: first cleans up the previous state (answers + seeds), then re-seeds
# the "broken" resources needed for the troubleshooting exercises.
# Contains NO solution: only the starting state.
set -uo pipefail

# Health gate: API/nodes/CNI + auto-repair of the expired Calico token (snapshot restore).
bash /vagrant/check-cluster-health.sh || exit 1

GOOD_IMG="nginx:1.29-alpine"     # valid image
BAD_IMG="nginx:1.29-nope"        # nonexistent tag (broken-image exercise)
BUSYBOX="busybox:1.36"

echo "🧹 Cleaning up the previous state (idempotent)…"
kubectl delete ns rbac-test workloads netpol storage trouble --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete pv pv-manual --ignore-not-found >/dev/null 2>&1
kubectl label node w1 disktype- >/dev/null 2>&1 || true
kubectl uncordon w1 w2 >/dev/null 2>&1 || true
sudo rm -f /opt/etcd-backup.db 2>/dev/null || true

# Wait for the namespaces to really disappear (finalizers) before recreating
for ns in rbac-test workloads netpol storage trouble; do
  kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true
done

echo "📦 etcd-client (for the snapshot exercise)…"
if ! command -v etcdctl >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y etcd-client >/dev/null 2>&1 \
    && echo "   etcdctl installed" || echo "   ⚠️ etcd-client install failed (network?) — the etcd exercise is still doable via the etcd pod"
fi

echo "🌱 Creating the namespaces…"
for ns in rbac-test workloads netpol storage trouble; do
  # retry while the old ns is still Terminating (create fails otherwise)
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns unavailable (still Terminating?)"; break; }
    sleep 2
  done
done

# ──────────────────────────────────────────────────────────────────────────────
# SEED — Services & Networking: NetworkPolicy (netpol)
#   backend (app=backend, listens on :80) + Service backend
#   frontend (app=frontend) and client (app=other) = testers
#   No NetworkPolicy created → everything is allowed at first (the exercise asks for it)
# ──────────────────────────────────────────────────────────────────────────────
echo "🌱 Seed netpol…"
kubectl -n netpol apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: backend, namespace: netpol, labels: { app: backend } }
spec:
  containers:
  - { name: web, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: backend, namespace: netpol }
spec:
  selector: { app: backend }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Pod
metadata: { name: frontend, namespace: netpol, labels: { app: frontend } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
---
apiVersion: v1
kind: Pod
metadata: { name: client, namespace: netpol, labels: { app: other } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# ──────────────────────────────────────────────────────────────────────────────
# SEED — Troubleshooting (trouble)
# ──────────────────────────────────────────────────────────────────────────────
echo "🌱 Seed trouble…"

# T13 — broken image (ImagePullBackOff)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: tshoot-web, namespace: trouble }
spec:
  replicas: 2
  selector: { matchLabels: { app: tshoot-web } }
  template:
    metadata: { labels: { app: tshoot-web } }
    spec:
      containers:
      - { name: web, image: ${BAD_IMG}, ports: [{ containerPort: 80 }] }
EOF

# T14 — Service with wrong selector (0 endpoint)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: api, namespace: trouble }
spec:
  replicas: 2
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
      - { name: api, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: api-svc, namespace: trouble }
spec:
  selector: { app: apiv1 }          # BUG : no Pod carries this label
  ports: [{ port: 80, targetPort: 80 }]
EOF

# T15 — Pod Pending (absurd memory request)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: hungry, namespace: trouble }
spec:
  containers:
  - name: web
    image: ${GOOD_IMG}
    resources: { requests: { memory: "100Gi", cpu: "50" } }   # BUG : inschedulable
EOF

# T16 — Deployment stuck: missing volume ConfigMap (CreateContainerConfigError)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: cfg-app, namespace: trouble }
spec:
  replicas: 1
  selector: { matchLabels: { app: cfg-app } }
  template:
    metadata: { labels: { app: cfg-app } }
    spec:
      containers:
      - name: web
        image: ${GOOD_IMG}
        volumeMounts: [{ name: cfg, mountPath: /etc/appcfg }]
      volumes:
      - name: cfg
        configMap: { name: cfg-app-config }   # BUG : this ConfigMap does not exist
EOF

echo
echo "✅ Exam environment ready."
echo "   • Open the exam: lab-setup/mock-exam/exam-01/EXAM.md"
echo "   • Suggested timer: 2 h."
echo "   • Grade at the end: bash /vagrant/mock-exam/exam-01/grade.sh"
