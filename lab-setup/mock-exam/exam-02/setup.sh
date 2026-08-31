#!/usr/bin/env bash
# setup.sh — prepares CKA mock exam #2 (advanced level) on the lab cluster.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/setup.sh"
#
# Idempotent: first cleans up the previous state (answers + seeds), then re-seeds
# the "broken" resources needed for the troubleshooting exercises.
# Contains NO solution: only the starting state.
# No "vagrant destroy" needed: everything happens at the K8s object level.
set -uo pipefail

# Health gate: API/nodes/CNI + auto-repair of the expired Calico token (snapshot restore).
bash /vagrant/check-cluster-health.sh || exit 1

GOOD_IMG="nginx:1.29-alpine"     # valid image
BUSYBOX="busybox:1.36"

echo "🧹 Cleaning up previous state (idempotent)…"
kubectl delete ns platform apps secure storage trouble --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete clusterrole deploy-admin --ignore-not-found >/dev/null 2>&1
kubectl delete clusterrolebinding ci-bot-deploy --ignore-not-found >/dev/null 2>&1
kubectl delete pv pv-fast --ignore-not-found >/dev/null 2>&1
kubectl taint node w1 dedicated- >/dev/null 2>&1 || true
kubectl label node w1 disktype- >/dev/null 2>&1 || true
kubectl label node w2 disktype- >/dev/null 2>&1 || true
kubectl uncordon w1 w2 >/dev/null 2>&1 || true

# Wait for the namespaces to truly disappear (finalizers) before recreating
for ns in platform apps secure storage trouble; do
  kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true
done

# Warn if the cluster was already upgraded by a previous T2 (irreversible)
cpver=$(kubectl get node cp1 -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
case "$cpver" in
  v1.34.*) : ;;  # expected starting state
  v1.35.*) echo "⚠️ cp1 is already on $cpver: T2 (upgrade) has already been done. To retake the exam, redeploy the cluster: vagrant destroy -f && vagrant up --no-parallel" ;;
  *) echo "ℹ️  cp1 version = ${cpver:-unknown}" ;;
esac

echo "🌱 Seeding namespaces…"
for ns in platform apps secure storage trouble; do
  # retry while the old ns is still Terminating (create fails otherwise)
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns unavailable (still Terminating?)"; break; }
    sleep 2
  done
done

# ──────────────────────────────────────────────────────────────────────────────
# SEED — Services & Networking: NetworkPolicy default-deny (secure)
#   db (app=db, listens on :80) + Service db; web (app=web) and scanner (app=other)
#   No NetworkPolicy created → everything is allowed initially (the task asks to lock it down)
# ──────────────────────────────────────────────────────────────────────────────
echo "🌱 Seed secure…"
kubectl -n secure apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: db, namespace: secure, labels: { app: db } }
spec:
  containers:
  - { name: web, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: db, namespace: secure }
spec:
  selector: { app: db }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Pod
metadata: { name: web, namespace: secure, labels: { app: web } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
---
apiVersion: v1
kind: Pod
metadata: { name: scanner, namespace: secure, labels: { app: other } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# ──────────────────────────────────────────────────────────────────────────────
# SEED — Troubleshooting (trouble)
# ──────────────────────────────────────────────────────────────────────────────
echo "🌱 Seed trouble…"

# T13 — readinessProbe broken (pods never Ready → 0 available)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: frontend, namespace: trouble }
spec:
  replicas: 2
  selector: { matchLabels: { app: frontend } }
  template:
    metadata: { labels: { app: frontend } }
    spec:
      containers:
      - name: web
        image: ${GOOD_IMG}
        ports: [{ containerPort: 80 }]
        readinessProbe:
          httpGet: { path: /, port: 8080 }   # BUG: nginx listens on 80, not 8080
          initialDelaySeconds: 3
          periodSeconds: 5
EOF

# T14 — Broken DNS resolution (dnsConfig to an unreachable server)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: dns-check, namespace: trouble, labels: { app: dns-check } }
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers: ["192.0.2.53"]   # BUG: unreachable DNS server (TEST-NET RFC 5737) → no resolution
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# T15 — Pod Pending (impossible placement constraint)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: stuck, namespace: trouble }
spec:
  nodeSelector: { disktype: nvme }   # BUG : no node has this label
  containers:
  - { name: web, image: ${GOOD_IMG} }
EOF

# T16 — Deployment stuck: missing env Secret (CreateContainerConfigError)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: billing, namespace: trouble }
spec:
  replicas: 1
  selector: { matchLabels: { app: billing } }
  template:
    metadata: { labels: { app: billing } }
    spec:
      containers:
      - name: web
        image: ${GOOD_IMG}
        env:
        - name: API_KEY
          valueFrom:
            secretKeyRef: { name: billing-secret, key: API_KEY }   # BUG : this Secret does not exist
EOF

echo
echo "✅ Exam #2 environment ready."
echo "   • Open the exam: lab-setup/mock-exam/exam-02/EXAM.md"
echo "   • Suggested timer: 2 h."
echo "   • Grade at the end: bash /vagrant/mock-exam/exam-02/grade.sh"
