#!/usr/bin/env bash
# setup.sh — prepares the themed lab "Cross-cutting Troubleshooting (all domains)".
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/setup.sh"
#
# Principle: EVERYTHING is broken at the start. The candidate must FIX it (see LAB.md).
# Idempotent: it first cleans up the previous state (including repairs from a previous
# run: cordoned/tainted nodes, static manifest on cp1, blocked finalizers),
# then re-seeds the "broken" state. Contains NO solution.
set -uo pipefail

# Health gate: API/nodes/CNI + auto-repair of the expired Calico token (snapshot restore).
bash /vagrant/check-cluster-health.sh || exit 1

GOOD_IMG="nginx:1.29-alpine"     # valid image
BAD_IMG="nginx:1.29-nope"        # nonexistent tag (ImagePullBackOff)
BUSYBOX="busybox:1.36"
NSES="ts-arch ts-nodes ts-work ts-net ts-netpol ts-storage"
STATIC_MANIFEST="/etc/kubernetes/manifests/ts-static.yaml"

echo "🧹 Cleaning up the previous state (idempotent)…"

# 0) Clear any ConfigMap stuck in Terminating (finalizer) from a previous run,
#    otherwise deleting the ts-arch namespace would stay blocked.
kubectl -n ts-arch patch cm stuck-cm --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true

# 1) Remove the broken static pod placed on cp1 (the kubelet will delete the mirror pod).
sudo rm -f "$STATIC_MANIFEST" 2>/dev/null || true

# 2) Reset the node state (in case a previous run was repaired/left as-is).
kubectl uncordon w1 w2 >/dev/null 2>&1 || true
kubectl taint node w1 maintenance- >/dev/null 2>&1 || true
kubectl label node w1 role- >/dev/null 2>&1 || true
kubectl label node w1 w2 cp1 disktype- >/dev/null 2>&1 || true

# 3) Delete namespaces + PV (cluster-scoped), then wait for them to actually disappear.
kubectl delete ns $NSES --ignore-not-found >/dev/null 2>&1 || true
kubectl delete pv pv-small pv-app --ignore-not-found >/dev/null 2>&1 || true
for ns in $NSES; do
  kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true
done
kubectl wait --for=delete pv/pv-small pv/pv-app --timeout=60s >/dev/null 2>&1 || true

echo "🌱 Recreating the namespaces…"
for ns in $NSES; do
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns unavailable (Terminating?)"; break; }
    sleep 2
  done
done

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN ARCH — Cluster Architecture & Nodes
# ══════════════════════════════════════════════════════════════════════════════

# A1 — Broken RBAC: the RoleBinding targets a wrong subject (typo) → deploy-bot has no permissions.
echo "🌱 A1 (broken RBAC)…"
kubectl -n ts-arch create sa deploy-bot >/dev/null 2>&1
kubectl -n ts-arch apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: pod-reader, namespace: ts-arch }
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: deploy-bot-read, namespace: ts-arch }
subjects:
- kind: ServiceAccount
  name: deploy-bot-typo          # BUG : this ServiceAccount does not exist (the correct one is deploy-bot)
  namespace: ts-arch
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# A4 — ConfigMap stuck in Terminating (unresolved finalizer).
echo "🌱 A4 (object stuck Terminating)…"
kubectl -n ts-arch apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: stuck-cm
  namespace: ts-arch
  finalizers: ["example.com/hold"]   # BUG : no controller removes this finalizer
data: { note: "delete me cleanly" }
EOF
kubectl -n ts-arch delete cm stuck-cm --wait=false >/dev/null 2>&1 || true

# A2 — Static pod broken on cp1 (wrong image tag → ImagePullBackOff).
echo "🌱 A2 (broken static pod on cp1)…"
sudo tee "$STATIC_MANIFEST" >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ts-static
  namespace: default
  labels: { app: ts-static }
spec:
  containers:
  - name: web
    image: ${BAD_IMG}          # BUG: nonexistent tag
    ports: [{ containerPort: 80 }]
EOF

# A3 — Node w1 "out of service": cordoned + NoSchedule taint, with a Deployment pinned to it.
echo "🌱 A3 (node w1 out of service)…"
kubectl label node w1 role=billing --overwrite >/dev/null 2>&1
kubectl cordon w1 >/dev/null 2>&1
kubectl taint node w1 maintenance=true:NoSchedule --overwrite >/dev/null 2>&1
kubectl -n ts-nodes apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: billing, namespace: ts-nodes }
spec:
  replicas: 1
  selector: { matchLabels: { app: billing } }
  template:
    metadata: { labels: { app: billing } }
    spec:
      nodeSelector: { role: billing }   # forced onto w1 (only labelled node) → blocked by cordon + taint
      containers:
      - { name: web, image: ${GOOD_IMG} }
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN WORK — Workloads & Scheduling
# ══════════════════════════════════════════════════════════════════════════════

# W1 — ImagePullBackOff (Deployment, image to fix).
echo "🌱 W1 (ImagePullBackOff)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: ts-work }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - { name: web, image: ${BAD_IMG} }   # BUG: nonexistent tag
EOF

# W2 — CrashLoopBackOff (command that exits with an error).
echo "🌱 W2 (CrashLoopBackOff)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: crasher, namespace: ts-work, labels: { app: crasher } }
spec:
  containers:
  - name: c
    image: ${BUSYBOX}
    command: ["sh","-c","echo starting; exit 1"]   # BUG: exits immediately with an error
EOF

# W3 — CreateContainerConfigError (missing Secret key).
echo "🌱 W3 (missing Secret key)…"
kubectl -n ts-work create secret generic app-secret --from-literal=username=admin >/dev/null 2>&1
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: checkout, namespace: ts-work, labels: { app: checkout } }
spec:
  containers:
  - name: c
    image: ${BUSYBOX}
    command: ["sh","-c","sleep 100000"]
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef: { name: app-secret, key: password }   # BUG: the 'password' key does not exist
EOF

# W4 — Pending (absurd memory request).
echo "🌱 W4 (Pending — requests)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: report, namespace: ts-work, labels: { app: report } }
spec:
  containers:
  - name: c
    image: ${GOOD_IMG}
    resources: { requests: { memory: "100Gi", cpu: "40" } }   # BUG: unschedulable
EOF

# W5 — Pending (nodeSelector matching no node).
echo "🌱 W5 (Pending — nodeSelector)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: analytics, namespace: ts-work, labels: { app: analytics } }
spec:
  nodeSelector: { disktype: ssd }   # BUG: no node carries this label
  containers:
  - { name: c, image: ${GOOD_IMG} }
EOF

# W6 — Wrong readiness probe (pods Running but never Ready).
echo "🌱 W6 (readiness broken)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: frontend, namespace: ts-work }
spec:
  replicas: 1
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
          periodSeconds: 5
EOF

# W7 — OOMKilled: the app needs ~50Mi in /dev/shm but the memory limit is 16Mi.
echo "🌱 W7 (OOMKilled — memory limit too low)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: cruncher, namespace: ts-work, labels: { app: cruncher } }
spec:
  containers:
  - name: c
    image: ${BUSYBOX}
    command: ["sh","-c","dd if=/dev/zero of=/dev/shm/data bs=1M count=50 >/dev/null 2>&1; sleep 100000"]
    resources:
      requests: { memory: "32Mi" }
      limits:   { memory: "32Mi" }   # BUG: tmpfs pages count against the limit → OOM-killed
EOF

# W8 — securityContext: nginx cannot start as an arbitrary non-root uid.
echo "🌱 W8 (securityContext breaks startup)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: locked-web, namespace: ts-work, labels: { app: locked-web } }
spec:
  securityContext: { runAsUser: 4321, runAsGroup: 4321 }   # BUG: this image needs root to start
  containers:
  - name: web
    image: ${GOOD_IMG}
    ports: [{ containerPort: 80 }]
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN NET — Services & Networking
# ══════════════════════════════════════════════════════════════════════════════

# N1 — Service with no endpoints (selector that doesn't match).
echo "🌱 N1 (selector → 0 endpoint)…"
kubectl -n ts-net apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: api, namespace: ts-net }
spec:
  replicas: 1
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
      - { name: api, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: api-svc, namespace: ts-net }
spec:
  selector: { app: api-v1 }          # BUG : no Pod carries this label
  ports: [{ port: 80, targetPort: 80 }]
EOF

# N2 — Service with wrong targetPort (endpoints present but traffic broken).
echo "🌱 N2 (wrong targetPort)…"
kubectl -n ts-net apply -f - >/dev/null 2>&1 <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: shop, namespace: ts-net }
spec:
  replicas: 1
  selector: { matchLabels: { app: shop } }
  template:
    metadata: { labels: { app: shop } }
    spec:
      containers:
      - { name: web, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: shop-svc, namespace: ts-net }
spec:
  selector: { app: shop }
  ports: [{ port: 80, targetPort: 8080 }]   # BUG: the container listens on 80
---
apiVersion: v1
kind: Pod
metadata: { name: shop-client, namespace: ts-net, labels: { app: shop-client } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# N4 — DNS: Pod with dnsPolicy Default (doesn't resolve cluster services).
echo "🌱 N4 (dnsPolicy Default)…"
kubectl -n ts-net apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: dns-broken, namespace: ts-net, labels: { app: dns-broken } }
spec:
  dnsPolicy: Default                 # BUG: does not use CoreDNS → no *.svc.cluster.local resolution
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# N3 — default-deny NetworkPolicy blocking legitimate traffic (dedicated namespace).
echo "🌱 N3 (blocking NetworkPolicy)…"
kubectl -n ts-netpol apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: backend, namespace: ts-netpol, labels: { app: backend } }
spec:
  containers:
  - { name: web, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: backend, namespace: ts-netpol }
spec:
  selector: { app: backend }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Pod
metadata: { name: client, namespace: ts-netpol, labels: { app: client } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: ts-netpol }
spec:
  podSelector: {}                    # BUG: blocks ALL ingress, including client → backend
  policyTypes: ["Ingress"]
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN STO — Storage
# ══════════════════════════════════════════════════════════════════════════════

# S1 — PVC Pending (storageClassName matching no PV).
echo "🌱 S1 (PVC Pending — sc)…"
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-small }
spec:
  capacity: { storage: 5Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: slow
  hostPath: { path: /mnt/ts-pv-small, type: DirectoryOrCreate }
EOF
kubectl -n ts-storage apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: ts-storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast            # BUG : no PV (or provisioner) in class 'fast'
  resources: { requests: { storage: 3Gi } }
EOF

# S2 — Pod stuck: the referenced PVC doesn't exist.
echo "🌱 S2 (missing PVC)…"
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-app }
spec:
  capacity: { storage: 5Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local
  hostPath: { path: /mnt/ts-pv-app, type: DirectoryOrCreate }
EOF
kubectl -n ts-storage apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: ts-storage, labels: { app: app } }
spec:
  containers:
  - name: web
    image: ${GOOD_IMG}
    volumeMounts: [{ name: data, mountPath: /data }]
  volumes:
  - name: data
    persistentVolumeClaim: { claimName: app-pvc }   # BUG : the 'app-pvc' PVC does not exist
EOF

echo
echo "✅ Troubleshooting environment ready — EVERYTHING is broken, it's up to you to fix it."
echo "   • Tasks     : lab-setup/labs/lab-troubleshooting/LAB.md"
echo "   • Grade     : bash /vagrant/labs/lab-troubleshooting/grade.sh"
echo "   • Node state:"
kubectl get nodes -o custom-columns=NODE:.metadata.name,STATUS:.status.conditions[-1].type,SCHED:.spec.unschedulable,TAINTS:.spec.taints[*].key 2>/dev/null
