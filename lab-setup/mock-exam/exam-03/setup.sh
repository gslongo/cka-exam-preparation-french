#!/usr/bin/env bash
# setup.sh — prepares CKA mock exam #3 (targeted drills) on the lab cluster.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/setup.sh"
#
# Idempotent: cleans up the previous state first (answers + seeds), then re-seeds
# the starting state. Contains NO solution.
set -uo pipefail

BASE=/opt/exam-03

echo "🧹 Cleaning up the previous state (idempotent)…"
sudo rm -rf "$BASE"
sudo mkdir -p "$BASE"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T1: "external" kubeconfig to analyze
#   3 contexts / 3 users; user audit-user carries a client-certificate-data.
#   The base64 is generated at runtime → always consistent with decoding.
echo "🌱 Seed T1 (external kubeconfig)…"
CERT_PEM="-----BEGIN CERTIFICATE-----
MIIBkTCB+wIUAuditUserFakeCertForCkaDrill0011223344NwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJYXVkaXQtdXNlcjAeFw0yNjAxMDEwMDAwMDBaFw0yNzAxMDEw
MDAwMDBaMBQxEjAQBgNVBAMMCWF1ZGl0LXVzZXIwWTATBgcqhkjOPQIBBggqhkjOPQMB
BwNCAAQfakefakefakefakefakefakefakefakefakefakefakefakefakefakefake
o1MwUTAdBgNVHQ4EFgQUAuditUserDrillKeyIdentifier00wHwYDVR0jBBgwFoAUAudi
tUserDrillKeyIdentifier00MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQAD
QQAfakeSignatureBytesForTheAuditUserDrillCertificateOnlyUsedForGrading
=
-----END CERTIFICATE-----"
CERTDATA=$(printf '%s\n' "$CERT_PEM" | base64 -w0)

sudo tee "$BASE/kubeconfig" >/dev/null <<EOF
apiVersion: v1
kind: Config
preferences: {}
clusters:
- name: cluster-alpha
  cluster:
    server: https://10.20.0.1:6443
- name: cluster-beta
  cluster:
    server: https://10.20.0.2:6443
users:
- name: audit-user
  user:
    client-certificate-data: ${CERTDATA}
- name: deployer
  user:
    token: drill-token-deployer
- name: viewer
  user:
    token: drill-token-viewer
contexts:
- name: alpha-audit
  context:
    cluster: cluster-alpha
    user: audit-user
- name: beta-deployer
  context:
    cluster: cluster-beta
    user: deployer
- name: beta-viewer
  context:
    cluster: cluster-beta
    user: viewer
current-context: beta-deployer
EOF

# The directory must be writable by the candidate (writing the answer files).
sudo chmod -R 0777 "$BASE"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T2: Helm + cert-manager + ClusterIssuer
#   Ensures helm is present (like on the real exam), cleans up any previous
#   cert-manager install, and seeds a ClusterIssuer to complete.
echo "🌱 Seed T2 (Helm / cert-manager)…"
if ! command -v helm >/dev/null 2>&1; then
  echo "   📦 helm missing → installing…"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash >/dev/null 2>&1
fi
# Idempotent cleanup of a previous cert-manager install
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found >/dev/null 2>&1 || true
if helm status certman -n pki >/dev/null 2>&1; then helm uninstall certman -n pki >/dev/null 2>&1 || true; fi
kubectl delete ns pki --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/pki --timeout=90s >/dev/null 2>&1 || true
kubectl get crd -o name 2>/dev/null | grep 'cert-manager.io' | xargs -r kubectl delete >/dev/null 2>&1 || true

# ClusterIssuer to complete (crlDistributionPoints is missing under spec.selfSigned)
sudo tee "$BASE/issuer.yaml" >/dev/null <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
sudo chmod 0666 "$BASE/issuer.yaml"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T3: StatefulSet to scale (replica reduction)
#   3 replicas at the start; the candidate must scale down to 1.
echo "🌱 Seed T3 (StatefulSet to scale)…"
kubectl delete ns project-store --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/project-store --timeout=60s >/dev/null 2>&1 || true
kubectl create ns project-store >/dev/null 2>&1
kubectl -n project-store apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: store
spec:
  clusterIP: None
  selector:
    app: store-db
  ports:
  - port: 80
    name: web
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: store-db
spec:
  serviceName: store
  replicas: 3
  selector:
    matchLabels:
      app: store-db
  template:
    metadata:
      labels:
        app: store-db
    spec:
      containers:
      - name: web
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
          name: web
EOF

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T4: QoS classes (eviction under node-pressure)
#   Pods of the 3 classes; BestEffort are evicted first.
echo "🌱 Seed T4 (QoS classes)…"
kubectl delete ns project-qos --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/project-qos --timeout=60s >/dev/null 2>&1 || true
kubectl create ns project-qos >/dev/null 2>&1
kubectl -n project-qos apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-cache          # BestEffort (no request/limit)
spec:
  containers:
  - name: c
    image: nginx:1.29-alpine
---
apiVersion: v1
kind: Pod
metadata:
  name: log-agent          # BestEffort (no request/limit)
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: ["sh","-c","sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: api-server         # Burstable (requests seulement)
spec:
  containers:
  - name: c
    image: nginx:1.29-alpine
    resources:
      requests:
        cpu: 50m
        memory: 32Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: worker             # Burstable (requests < limits)
spec:
  containers:
  - name: c
    image: nginx:1.29-alpine
    resources:
      requests:
        cpu: 50m
        memory: 32Mi
      limits:
        cpu: 100m
        memory: 64Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: db-core            # Guaranteed (requests == limits, cpu ET mem)
spec:
  containers:
  - name: c
    image: nginx:1.29-alpine
    resources:
      requests:
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 64Mi
EOF

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T5: HPA + Kustomize (base + staging/prod overlays)
#   "before" state: Deployment + ConfigMap deployed, no HPA. The candidate must
#   remove the ConfigMap, add an HPA (patched in prod) and re-apply.
echo "🌱 Seed T5 (HPA / Kustomize)…"
kubectl delete ns api-gw-staging api-gw-prod --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/api-gw-staging ns/api-gw-prod --timeout=60s >/dev/null 2>&1 || true
KDIR="$BASE/kustomize/api-gw"
sudo rm -rf "$BASE/kustomize"
sudo mkdir -p "$KDIR/base" "$KDIR/overlays/staging" "$KDIR/overlays/prod"

sudo tee "$KDIR/base/deployment.yaml" >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gw
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gw
  template:
    metadata:
      labels:
        app: api-gw
    spec:
      containers:
      - name: api-gw
        image: nginx:1.29-alpine
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
EOF

sudo tee "$KDIR/base/configmap.yaml" >/dev/null <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: scaling-config
data:
  externalAutoscaler: "legacy"
  threshold: "80"
EOF

sudo tee "$KDIR/base/kustomization.yaml" >/dev/null <<'EOF'
resources:
- deployment.yaml
- configmap.yaml
EOF

sudo tee "$KDIR/overlays/staging/kustomization.yaml" >/dev/null <<'EOF'
namespace: api-gw-staging
resources:
- ../../base
EOF

sudo tee "$KDIR/overlays/prod/kustomization.yaml" >/dev/null <<'EOF'
namespace: api-gw-prod
resources:
- ../../base
EOF

# Namespaces + initial deployment (ConfigMap present, no HPA)
kubectl create ns api-gw-staging >/dev/null 2>&1
kubectl create ns api-gw-prod    >/dev/null 2>&1
kubectl kustomize "$KDIR/overlays/staging" | kubectl apply -f - >/dev/null 2>&1
kubectl kustomize "$KDIR/overlays/prod"    | kubectl apply -f - >/dev/null 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T6: PV + PVC (without SC) + Deployment that mounts the volume
#   We only create the Namespace; the candidate creates PV, PVC and Deployment.
echo "🌱 Seed T6 (Storage: PV/PVC + Deployment)…"
kubectl delete deployment webstore -n storage-app --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns storage-app --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/storage-app --timeout=60s >/dev/null 2>&1 || true
kubectl delete pv data-pv --ignore-not-found >/dev/null 2>&1 || true
kubectl create ns storage-app >/dev/null 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T7: metrics-server / kubectl top (the candidate writes 2 scripts)
#   Ensures metrics-server is installed (kubectl top must work).
echo "🌱 Seed T7 (metrics-server / kubectl top)…"
if ! kubectl get deploy metrics-server -n kube-system >/dev/null 2>&1; then
  echo "   📊 metrics-server missing → installing…"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null 2>&1
  kubectl -n kube-system rollout status deploy/metrics-server --timeout=150s >/dev/null 2>&1 || true
fi

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T8: kubeadm join + worker upgrade (the candidate writes 2 files)
#   Nothing to seed in the cluster: the candidate generates the join command
#   from the control plane and writes the upgrade runbook. We clean up its answers.
echo "🌱 Seed T8 (kubeadm join + upgrade node)…"
rm -f "$BASE/join-command.txt" "$BASE/upgrade-node.sh"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T9: Kubernetes API from a Pod (SA + curl + mounted token)
#   ns project-audit, SA probe-sa allowed (Role) to list the ns Secrets,
#   a Secret to discover. The candidate creates the Pod, curls the API, writes the JSON.
echo "🌱 Seed T9 (API from a Pod: SA + curl)…"
kubectl delete pod secret-probe -n project-audit --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns project-audit --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/project-audit --timeout=60s >/dev/null 2>&1 || true
rm -f "$BASE/secrets.json"
kubectl create ns project-audit >/dev/null 2>&1
kubectl -n project-audit create sa probe-sa >/dev/null 2>&1
kubectl -n project-audit create role secret-reader --verb=get,list,watch --resource=secrets >/dev/null 2>&1
kubectl -n project-audit create rolebinding probe-sa-secrets --role=secret-reader --serviceaccount=project-audit:probe-sa >/dev/null 2>&1
kubectl -n project-audit create secret generic audit-key --from-literal=api-key=s3cr3t-value >/dev/null 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T10: DaemonSet on all nodes (the candidate creates the DaemonSet)
#   We only create the Namespace project-batch.
echo "🌱 Seed T10 (DaemonSet)…"
kubectl delete ds log-harvester -n project-batch --ignore-not-found >/dev/null 2>&1 || true
kubectl create ns project-batch >/dev/null 2>&1 || true
# Removes a residual taint (e.g. exam-02 T7 dedicated=cka): the workers must be
# schedulable so that only the control-plane toleration remains necessary for T10.
kubectl taint nodes --all dedicated- >/dev/null 2>&1 || true

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T11: multi-container Deployment + anti-affinity (candidate creates the Deploy)
echo "🌱 Seed T11 (Deployment anti-affinity)…"
kubectl delete deploy edge-cache -n project-batch --ignore-not-found >/dev/null 2>&1 || true

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T13: kubeadm certificates (the candidate writes 2 files)
echo "🌱 Seed T13 (kubeadm certificates)…"
rm -f "$BASE/apiserver-expiration" "$BASE/renew-apiserver.sh"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T14: NetworkPolicy egress (candidate creates the NP; we seed the target Pods)
echo "🌱 Seed T14 (NetworkPolicy egress)…"
kubectl delete ns project-mesh --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/project-mesh --timeout=60s >/dev/null 2>&1 || true
kubectl create ns project-mesh >/dev/null 2>&1
# agnhost: backend = client (/agnhost binary to test runtime enforcement),
#           cache-a/cache-b/vault = TCP listeners on their application port.
AGN=registry.k8s.io/e2e-test-images/agnhost:2.53
kubectl -n project-mesh run backend-1 --image="$AGN" --labels=app=backend --command -- /agnhost pause >/dev/null 2>&1
kubectl -n project-mesh run cache-a-1 --image="$AGN" --labels=app=cache-a --command -- /agnhost netexec --http-port=6379 >/dev/null 2>&1
kubectl -n project-mesh run cache-b-1 --image="$AGN" --labels=app=cache-b --command -- /agnhost netexec --http-port=5432 >/dev/null 2>&1
kubectl -n project-mesh run vault-1   --image="$AGN" --labels=app=vault   --command -- /agnhost netexec --http-port=9999 >/dev/null 2>&1
kubectl -n project-mesh wait --for=condition=Ready pod --all --timeout=120s >/dev/null 2>&1 || true

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T16: Pod to audit via crictl (pinned to cp1 for a local crictl)
echo "🌱 Seed T16 (crictl debug)…"
kubectl get ns project-batch >/dev/null 2>&1 || kubectl create ns project-batch >/dev/null 2>&1
kubectl -n project-batch delete pod probe-httpd --ignore-not-found >/dev/null 2>&1 || true
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: probe-httpd
  namespace: project-batch
spec:
  nodeName: cp1
  containers:
  - name: probe-httpd
    image: httpd:2-alpine
EOF
rm -f "$BASE/container-info.txt" "$BASE/container.log"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T12: Gateway API (CRDs + GatewayClass + Gateway; candidate creates HTTPRoute)
echo "🌱 Seed T12 (Gateway API)…"
if ! kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
  GWAPI_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest | grep -oP '"tag_name": "\K[^"]+')
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VER}/standard-install.yaml" >/dev/null 2>&1
fi
kubectl get ns project-edge >/dev/null 2>&1 || kubectl create ns project-edge >/dev/null 2>&1
kubectl -n project-edge delete httproute route-splitter --ignore-not-found >/dev/null 2>&1 || true
cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg-class
spec:
  controllerName: example.com/gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge-gw
  namespace: project-edge
spec:
  gatewayClassName: eg-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
EOF

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T15: CoreDNS custom domain (RESET DNS to its original at each run)
echo "🌱 Seed T15 (CoreDNS)…"
COREDNS_ORIG=/etc/exam-03-corefile.orig
# 1) Capture the original Corefile — only once, while it's still "clean"
if ! sudo test -f "$COREDNS_ORIG"; then
  kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | sudo tee "$COREDNS_ORIG" >/dev/null
fi
# 2) Restore the original Corefile (undoes any customization from a previous attempt)
COREDNS_PATCH=$(mktemp)
{ echo "data:"; echo "  Corefile: |"; sudo sed 's/^/    /' "$COREDNS_ORIG"; } > "$COREDNS_PATCH"
kubectl -n kube-system patch cm coredns --type merge --patch-file "$COREDNS_PATCH" >/dev/null 2>&1
rm -f "$COREDNS_PATCH"
kubectl -n kube-system rollout restart deployment coredns >/dev/null 2>&1
rm -f "$BASE/coredns_original.yaml"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T17: etcd introspection (read-only; we just clean up the answer file)
echo "🌱 Seed T17 (etcd introspection)…"
rm -f "$BASE/etcd-info.txt"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T18: kube-proxy / iptables (the candidate creates Pod+Service; we clean up)
echo "🌱 Seed T18 (kube-proxy iptables)…"
kubectl create ns project-proxy >/dev/null 2>&1 || true
kubectl -n project-proxy delete svc proxy-svc --now >/dev/null 2>&1 || true
kubectl -n project-proxy delete pod p-proxy --now >/dev/null 2>&1 || true
rm -f "$BASE/iptables.txt"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T19: Service CIDR multi-range (the candidate creates everything; we clean up)
echo "🌱 Seed T19 (Service CIDR multi-range)…"
kubectl create ns project-range >/dev/null 2>&1 || true
# delete the Services first (frees the IPAddress) before the ServiceCIDR
kubectl -n project-range delete svc range-svc range-svc2 --now >/dev/null 2>&1 || true
kubectl -n project-range delete pod range-probe --now >/dev/null 2>&1 || true
kubectl delete servicecidr extra-range --now >/dev/null 2>&1 || true

# All of /opt/exam-03 must remain writable by the candidate.
sudo chmod -R 0777 "$BASE"

echo "✅ Setup exam-03 done."
echo "   Available tasks: see EXAM.md. Grading: bash /vagrant/mock-exam/exam-03/grade.sh"
