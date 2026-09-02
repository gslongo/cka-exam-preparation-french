#!/usr/bin/env bash
# setup.sh — prepares CKA mock exam #4 (killer.sh drills — session 2) on the lab cluster.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-04/setup.sh"
#
# Idempotent: cleans up the previous state first (answers + seeds), then re-seeds
# the starting state. Contains NO solution.
set -uo pipefail

# T6 pre-repair: un-break the kubelet from a previous run BEFORE the health gate,
# otherwise the gate would fail on a NotReady cp1 and the setup could never reset itself.
if [ -f /etc/systemd/system/kubelet.service.d/99-kubeadm-extra.conf ]; then
  echo "🔧 Repairing kubelet from a previous run…"
  sudo rm -f /etc/systemd/system/kubelet.service.d/99-kubeadm-extra.conf
  sudo systemctl daemon-reload
  sudo systemctl enable --now kubelet >/dev/null 2>&1
  kubectl wait --for=condition=Ready node/cp1 --timeout=120s >/dev/null 2>&1 || true
fi

# T9 pre-repair: regenerate the scheduler manifest if a previous run left it parked
# (the health gate's CNI smoke pod needs a working scheduler).
if [ ! -f /etc/kubernetes/manifests/kube-scheduler.yaml ]; then
  echo "🔧 Restoring kube-scheduler from a previous run…"
  sudo kubeadm init phase control-plane scheduler >/dev/null 2>&1
  sleep 10
fi

# Health gate: API/nodes/CNI + auto-repair of the expired Calico token (snapshot restore).
bash /vagrant/check-cluster-health.sh || exit 1

BASE=/opt/exam-04
NSES="q4-control q4-workload q4-backup project-alpha project-beta project-gamma"

echo "🧹 Cleaning up the previous state (idempotent)…"
sudo rm -rf "$BASE"
sudo mkdir -p "$BASE" && sudo chmod 1777 "$BASE"
kubectl delete ns $NSES --ignore-not-found >/dev/null 2>&1 || true
for ns in $NSES; do kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true; done
# T10 leftovers: the SC and the RETAINED dynamically-provisioned PVs of previous runs.
kubectl delete sc local-backup --ignore-not-found >/dev/null 2>&1 || true
kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.storageClassName}{"\n"}{end}' 2>/dev/null \
  | awk '$2=="local-backup"{print $1}' | xargs -r kubectl delete pv >/dev/null 2>&1 || true

echo "🌱 Seeding namespaces…"
for ns in $NSES; do
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns unavailable (Terminating?)"; break; }
    sleep 2
  done
done

# ── T1 — DNS FQDNs: controller Deployment + ConfigMap, headless svc + stable-name Pod ──
echo "🌱 Seed T1 (controller / department / section100)…"
kubectl -n q4-control apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: controller-config, namespace: q4-control }
data:
  DNS_1: "fixme.local"
  DNS_2: "fixme.local"
  DNS_3: "fixme.local"
  DNS_4: "fixme.local"
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: controller, namespace: q4-control }
spec:
  replicas: 1
  selector: { matchLabels: { app: controller } }
  template:
    metadata: { labels: { app: controller } }
    spec:
      containers:
      - name: c
        image: busybox:1.36
        command: ["sh","-c","sleep 100000"]
        envFrom: [{ configMapRef: { name: controller-config } }]
EOF
kubectl -n q4-workload apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata: { name: department, namespace: q4-workload }
spec:
  clusterIP: None
  selector: { app: section }
  ports: [{ port: 80 }]
---
apiVersion: v1
kind: Service
metadata: { name: section, namespace: q4-workload }
spec:
  clusterIP: None
  selector: { app: section }
  ports: [{ port: 80 }]
---
apiVersion: v1
kind: Pod
metadata: { name: section100, namespace: q4-workload, labels: { app: section } }
spec:
  hostname: section100
  subdomain: section
  containers:
  - { name: c, image: busybox:1.36, command: ["sh","-c","sleep 100000"] }
EOF

# ── T2 — static pod + NodePort: nothing to seed, only undo a previous answer ──
echo "🌱 T2 cleanup (static pod my-static-pod + service)…"
sudo grep -l 'name: my-static-pod' /etc/kubernetes/manifests/*.yaml 2>/dev/null | xargs -r sudo rm -f
kubectl -n default delete svc static-pod-service --ignore-not-found >/dev/null 2>&1 || true
kubectl -n default wait --for=delete pod/my-static-pod-cp1 --timeout=60s >/dev/null 2>&1 || true

# ── T4 — probes: the Service pre-exists; undo any previous answer pods ──
echo "🌱 Seed T4 (Service service-am-i-ready)…"
kubectl -n default delete pod ready-if-service-ready am-i-ready --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
kubectl -n default apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata: { name: service-am-i-ready, namespace: default }
spec:
  selector: { id: cross-server-ready }
  ports: [{ port: 80, targetPort: 80 }]
EOF

# ── T10 — dynamic provisioning: install local-path-provisioner once + seed the Job file ──
if ! kubectl -n local-path-storage get deploy local-path-provisioner >/dev/null 2>&1; then
  echo "🌐 Installing local-path-provisioner…"
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml >/dev/null 2>&1
fi
echo "🌱 Seed T10 (backup Job to adjust)…"
cat > "$BASE/backup.yaml" <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: backup
  namespace: q4-backup
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: backup
        image: busybox:1.36
        command: ["sh", "-c", "cp /etc/hostname /backup/backup-$(date +%s) && ls -l /backup"]
        volumeMounts:
        - name: backup
          mountPath: /backup
      volumes:
      - name: backup
        emptyDir: {}   # TODO: back this with a PVC instead
EOF

# ── T11 — secrets: the candidate creates the namespace; we only clean + provide secret1.yaml ──
echo "🌱 Seed T11 (secret1.yaml — the namespace q4-secret is YOURS to create)…"
kubectl delete ns q4-secret --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/q4-secret --timeout=120s >/dev/null 2>&1 || true
cat > "$BASE/secret1.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: secret1
data:
  halt: aGFsdCB0aGUgcHJlc3Nlcw==
EOF

# ── T16 — Roles spread across the project-* namespaces (beta must win with 5) ──
echo "🌱 Seed T16 (Roles in project-* namespaces)…"
for i in 1 2; do kubectl -n project-alpha create role "role-$i" --verb=get --resource=pods >/dev/null 2>&1; done
for i in 1 2 3 4 5; do kubectl -n project-beta create role "role-$i" --verb=get --resource=pods >/dev/null 2>&1; done
kubectl -n project-gamma create role role-1 --verb=get --resource=pods >/dev/null 2>&1

# ── T17 — Kustomize operator: CRDs + RBAC (incomplete on purpose) + deploy ──
echo "🌱 Seed T17 (Kustomize operator)…"
kubectl delete ns q4-operator --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/q4-operator --timeout=120s >/dev/null 2>&1 || true
kubectl delete crd students.education.cka.local teachers.education.cka.local courses.education.cka.local --ignore-not-found >/dev/null 2>&1 || true
mkdir -p "$BASE/operator/base" "$BASE/operator/prod"
cat > "$BASE/operator/base/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ns.yaml
- crd.yaml
- rbac.yaml
- operator.yaml
- students.yaml
EOF
cat > "$BASE/operator/base/ns.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: q4-operator
EOF
cat > "$BASE/operator/base/crd.yaml" <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: students.education.cka.local
spec:
  group: education.cka.local
  scope: Namespaced
  names: { kind: Student, plural: students, singular: student }
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name: { type: string }
              description: { type: string }
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: teachers.education.cka.local
spec:
  group: education.cka.local
  scope: Namespaced
  names: { kind: Teacher, plural: teachers, singular: teacher }
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name: { type: string }
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: courses.education.cka.local
spec:
  group: education.cka.local
  scope: Namespaced
  names: { kind: Course, plural: courses, singular: course }
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name: { type: string }
EOF
cat > "$BASE/operator/base/rbac.yaml" <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: operator-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: operator-role
rules:
- apiGroups: ["education.cka.local"]
  resources: ["students"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: operator-rb
subjects:
- kind: ServiceAccount
  name: operator-sa
roleRef:
  kind: Role
  name: operator-role
  apiGroup: rbac.authorization.k8s.io
EOF
cat > "$BASE/operator/base/operator.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: operator
spec:
  replicas: 1
  selector: { matchLabels: { app: operator } }
  template:
    metadata: { labels: { app: operator } }
    spec:
      serviceAccountName: operator-sa
      containers:
      - name: operator
        # curl image: busybox wget cannot complete the TLS handshake with the apiserver
        image: curlimages/curl:latest
        command:
        - sh
        - -c
        - |
          NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
          CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          while true; do
            TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
            for r in students teachers courses; do
              code=$(curl -s -o /dev/null -w "%{http_code}" --cacert "$CA" \
                   -H "Authorization: Bearer $TOKEN" \
                   "https://kubernetes.default.svc/apis/education.cka.local/v1/namespaces/$NS/$r")
              if [ "$code" = "200" ]; then
                echo "OK: can list $r.education.cka.local"
              else
                echo "ERROR: cannot list $r.education.cka.local (RBAC forbidden?)"
              fi
            done
            sleep 20
          done
EOF
cat > "$BASE/operator/base/students.yaml" <<'EOF'
apiVersion: education.cka.local/v1
kind: Student
metadata:
  name: student1
spec: { name: "Anna", description: "first student" }
---
apiVersion: education.cka.local/v1
kind: Student
metadata:
  name: student2
spec: { name: "Ben", description: "second student" }
---
apiVersion: education.cka.local/v1
kind: Student
metadata:
  name: student3
spec: { name: "Cleo", description: "third student" }
EOF
cat > "$BASE/operator/prod/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: q4-operator
resources:
- ../base
EOF
# Deploy: CRDs must be Established before the Student CRs → two passes.
kubectl kustomize "$BASE/operator/prod" | kubectl apply -f - >/dev/null 2>&1 || true
kubectl wait --for=condition=Established crd/students.education.cka.local --timeout=60s >/dev/null 2>&1 || true
kubectl kustomize "$BASE/operator/prod" | kubectl apply -f - >/dev/null 2>&1

# ── T9 — manual scheduling: nothing to seed, only undo previous answer pods ──
echo "🌱 T9 cleanup (manual-schedule pods)…"
kubectl -n default delete pod manual-schedule manual-schedule2 --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true

# ── T12 — control-plane-only pod: nothing to seed, only undo a previous answer ──
kubectl -n default delete pod pod1 --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true

# ── T13 — multi-container playground: nothing to seed, only undo a previous answer ──
kubectl -n default delete pod multi-container-playground --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true

# ── T6 — break the kubelet on cp1 (LAST: everything else is already seeded) ──
echo "🌱 Seed T6 (kubelet down on cp1)…"
kubectl -n default delete pod success --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo tee /etc/systemd/system/kubelet.service.d/99-kubeadm-extra.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
sudo systemctl daemon-reload
sudo systemctl stop kubelet

echo ""
echo "✅ Mock exam #4 environment ready — 17 tasks, 100 pts, pass ≥ 66 %."
echo "   • Tasks : lab-setup/mock-exam/exam-04/EXAM.md"
echo "   • Grade : bash /vagrant/mock-exam/exam-04/grade.sh"
