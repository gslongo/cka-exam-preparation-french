#!/usr/bin/env bash
# setup.sh — prepare the "Workloads & Scheduling" lab (CKA domain 02).
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-workloads-scheduling/setup.sh"
#
# A BUILD lab: you author Deployments, DaemonSets, Jobs/CronJobs, an HPA and several
# scheduling constraints from scratch, then grade the result. setup.sh only creates the
# namespaces and one pre-existing Deployment to autoscale; everything else is YOUR job
# (see LAB.md). Idempotent: undoes any previous run, then re-seeds. Contains NO solutions.
set -uo pipefail

# Health gate: API/nodes/CNI + auto-repair of the expired Calico token (snapshot restore).
bash /vagrant/check-cluster-health.sh || exit 1

GOOD_IMG="nginx:1.29-alpine"
NSES="w-deploy w-ds w-batch w-hpa w-res w-sched w-taint w-spread w-prio"

echo "🧹 Cleaning up previous state (idempotent)…"
# Scheduling side-effects a previous solution may have left on the nodes.
kubectl uncordon w1 w2 >/dev/null 2>&1 || true
kubectl taint node w1 dedicated- >/dev/null 2>&1 || true
kubectl label node w2 disktype- >/dev/null 2>&1 || true
# Cluster-scoped object + all lab namespaces.
kubectl delete priorityclass high-priority --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns $NSES --ignore-not-found >/dev/null 2>&1 || true
for ns in $NSES; do kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true; done

echo "🌱 Seeding namespaces…"
for ns in $NSES; do
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns unavailable (Terminating?)"; break; }
    sleep 2
  done
done

# ── T6 — an existing Deployment (with CPU requests) waiting for an HPA ───────────
echo "🌱 Task 6 (Deployment 'hpa-target' to autoscale)…"
kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-target
  namespace: w-hpa
spec:
  replicas: 1
  selector: { matchLabels: { app: hpa-target } }
  template:
    metadata: { labels: { app: hpa-target } }
    spec:
      containers:
      - name: web
        image: ${GOOD_IMG}
        ports: [{ containerPort: 80 }]
        resources:
          requests: { cpu: 100m, memory: 32Mi }
          limits:   { cpu: 200m, memory: 64Mi }
EOF

echo ""
echo "✅ Workloads & Scheduling lab ready — build the 12 objects, then grade yourself."
echo "   • Tasks   : lab-setup/labs/lab-workloads-scheduling/LAB.md"
echo "   • Grade   : bash /vagrant/labs/lab-workloads-scheduling/grade.sh"
echo "   • Nodes   :"
kubectl get nodes 2>/dev/null | awk 'NR==1{printf "     %-6s %-9s %s\n",$1,$2,"ROLES"} NR>1{printf "     %-6s %-9s %s\n",$1,$2,$3}'
