#!/usr/bin/env bash
# setup.sh — prépare l'examen blanc CKA n°3 (drills ciblés) sur le cluster du lab.
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/setup.sh"
#
# Idempotent : nettoie d'abord l'état précédent (réponses + seeds), puis re-sème
# l'état de départ. NE contient AUCUNE solution.
set -uo pipefail

BASE=/opt/exam-03

echo "🧹 Nettoyage de l'état précédent (idempotent)…"
sudo rm -rf "$BASE"
sudo mkdir -p "$BASE"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T1 : kubeconfig « externe » à analyser
#   3 contextes / 3 users ; user audit-user porte un client-certificate-data.
#   Le base64 est généré à l'exécution → toujours cohérent avec le décodage.
echo "🌱 Seed T1 (kubeconfig externe)…"
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

# Le dossier doit être inscriptible par le candidat (écriture des fichiers réponses).
sudo chmod -R 0777 "$BASE"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T2 : Helm + cert-manager + ClusterIssuer
#   Assure la présence de helm (comme sur le vrai examen), nettoie toute install
#   cert-manager précédente, et sème un ClusterIssuer à compléter.
echo "🌱 Seed T2 (Helm / cert-manager)…"
if ! command -v helm >/dev/null 2>&1; then
  echo "   📦 helm absent → installation…"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash >/dev/null 2>&1
fi
# Nettoyage idempotent d'une install cert-manager précédente
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found >/dev/null 2>&1 || true
if helm status certman -n pki >/dev/null 2>&1; then helm uninstall certman -n pki >/dev/null 2>&1 || true; fi
kubectl delete ns pki --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/pki --timeout=90s >/dev/null 2>&1 || true
kubectl get crd -o name 2>/dev/null | grep 'cert-manager.io' | xargs -r kubectl delete >/dev/null 2>&1 || true

# ClusterIssuer à compléter (il manque crlDistributionPoints sous spec.selfSigned)
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
# SEED — T3 : StatefulSet à scaler (réduction de replicas)
#   3 replicas au départ ; le candidat doit descendre à 1.
echo "🌱 Seed T3 (StatefulSet à scaler)…"
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
# SEED — T4 : classes QoS (éviction sous node-pressure)
#   Pods des 3 classes ; les BestEffort sont évincés en premier.
echo "🌱 Seed T4 (QoS classes)…"
kubectl delete ns project-qos --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/project-qos --timeout=60s >/dev/null 2>&1 || true
kubectl create ns project-qos >/dev/null 2>&1
kubectl -n project-qos apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-cache          # BestEffort (aucune request/limit)
spec:
  containers:
  - name: c
    image: nginx:1.29-alpine
---
apiVersion: v1
kind: Pod
metadata:
  name: log-agent          # BestEffort (aucune request/limit)
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
# SEED — T5 : HPA + Kustomize (base + overlays staging/prod)
#   État "avant" : Deployment + ConfigMap déployés, aucun HPA. Le candidat doit
#   retirer la ConfigMap, ajouter un HPA (patché en prod) et ré-appliquer.
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

# Namespaces + déploiement initial (ConfigMap présente, pas d'HPA)
kubectl create ns api-gw-staging >/dev/null 2>&1
kubectl create ns api-gw-prod    >/dev/null 2>&1
kubectl kustomize "$KDIR/overlays/staging" | kubectl apply -f - >/dev/null 2>&1
kubectl kustomize "$KDIR/overlays/prod"    | kubectl apply -f - >/dev/null 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T6 : PV + PVC (sans SC) + Deployment qui monte le volume
#   On ne crée que le Namespace ; le candidat crée PV, PVC et Deployment.
echo "🌱 Seed T6 (Storage : PV/PVC + Deployment)…"
kubectl delete deployment webstore -n storage-app --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ns storage-app --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/storage-app --timeout=60s >/dev/null 2>&1 || true
kubectl delete pv data-pv --ignore-not-found >/dev/null 2>&1 || true
kubectl create ns storage-app >/dev/null 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T7 : metrics-server / kubectl top (le candidat écrit 2 scripts)
#   S'assure que metrics-server est installé (kubectl top doit fonctionner).
echo "🌱 Seed T7 (metrics-server / kubectl top)…"
if ! kubectl get deploy metrics-server -n kube-system >/dev/null 2>&1; then
  echo "   📊 metrics-server absent → installation…"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null 2>&1
  kubectl -n kube-system rollout status deploy/metrics-server --timeout=150s >/dev/null 2>&1 || true
fi

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T8 : jonction kubeadm + upgrade worker (le candidat écrit 2 fichiers)
#   Rien à semer dans le cluster : le candidat génère la commande de jonction
#   depuis le control plane et rédige le runbook d'upgrade. On nettoie ses réponses.
echo "🌱 Seed T8 (kubeadm join + upgrade node)…"
rm -f "$BASE/join-command.txt" "$BASE/upgrade-node.sh"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T9 : API Kubernetes depuis un Pod (SA + curl + token monté)
#   ns project-audit, SA probe-sa autorisée (Role) à lister les Secrets du ns,
#   un Secret à découvrir. Le candidat crée le Pod, curl l'API, écrit le JSON.
echo "🌱 Seed T9 (API depuis un Pod : SA + curl)…"
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
# SEED — T10 : DaemonSet sur tous les nœuds (le candidat crée le DaemonSet)
#   On ne crée que le Namespace project-batch.
echo "🌱 Seed T10 (DaemonSet)…"
kubectl delete ds log-harvester -n project-batch --ignore-not-found >/dev/null 2>&1 || true
kubectl create ns project-batch >/dev/null 2>&1 || true
# Retire un taint résiduel (ex. exam-02 T7 dedicated=cka) : les workers doivent être
# planifiables pour que seule la toleration control-plane reste nécessaire à T10.
kubectl taint nodes --all dedicated- >/dev/null 2>&1 || true

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T11 : Deployment multi-conteneurs + anti-affinité (candidat crée le Deploy)
echo "🌱 Seed T11 (Deployment anti-affinité)…"
kubectl delete deploy edge-cache -n project-batch --ignore-not-found >/dev/null 2>&1 || true

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T13 : certificats kubeadm (le candidat écrit 2 fichiers)
echo "🌱 Seed T13 (certificats kubeadm)…"
rm -f "$BASE/apiserver-expiration" "$BASE/renew-apiserver.sh"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T14 : NetworkPolicy egress (candidat crée la NP ; on sème les Pods cibles)
echo "🌱 Seed T14 (NetworkPolicy egress)…"
kubectl delete ns project-mesh --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/project-mesh --timeout=60s >/dev/null 2>&1 || true
kubectl create ns project-mesh >/dev/null 2>&1
kubectl -n project-mesh run backend-1 --image=nginx:1-alpine --labels=app=backend >/dev/null 2>&1
kubectl -n project-mesh run cache-a-1 --image=nginx:1-alpine --labels=app=cache-a >/dev/null 2>&1
kubectl -n project-mesh run cache-b-1 --image=nginx:1-alpine --labels=app=cache-b >/dev/null 2>&1
kubectl -n project-mesh run audit-1  --image=nginx:1-alpine --labels=app=audit  >/dev/null 2>&1

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T16 : Pod à auditer via crictl (épinglé sur cp1 pour un crictl local)
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
# SEED — T12 : Gateway API (CRDs + GatewayClass + Gateway ; candidat crée HTTPRoute)
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
# SEED — T15 : CoreDNS domaine personnalisé (RESET du DNS à l'origine à chaque run)
echo "🌱 Seed T15 (CoreDNS)…"
COREDNS_ORIG=/etc/exam-03-corefile.orig
# 1) Capture du Corefile d'origine — une seule fois, tant qu'il est encore "propre"
if ! sudo test -f "$COREDNS_ORIG"; then
  kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | sudo tee "$COREDNS_ORIG" >/dev/null
fi
# 2) Restaure le Corefile d'origine (annule toute personnalisation d'un essai précédent)
COREDNS_PATCH=$(mktemp)
{ echo "data:"; echo "  Corefile: |"; sudo sed 's/^/    /' "$COREDNS_ORIG"; } > "$COREDNS_PATCH"
kubectl -n kube-system patch cm coredns --type merge --patch-file "$COREDNS_PATCH" >/dev/null 2>&1
rm -f "$COREDNS_PATCH"
kubectl -n kube-system rollout restart deployment coredns >/dev/null 2>&1
rm -f "$BASE/coredns_original.yaml"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T17 : introspection etcd (read-only ; on nettoie juste le fichier réponse)
echo "🌱 Seed T17 (etcd introspection)…"
rm -f "$BASE/etcd-info.txt"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T18 : kube-proxy / iptables (le candidat crée Pod+Service ; on nettoie)
echo "🌱 Seed T18 (kube-proxy iptables)…"
kubectl create ns project-proxy >/dev/null 2>&1 || true
kubectl -n project-proxy delete svc proxy-svc --now >/dev/null 2>&1 || true
kubectl -n project-proxy delete pod p-proxy --now >/dev/null 2>&1 || true
rm -f "$BASE/iptables.txt"

# ──────────────────────────────────────────────────────────────────────────────
# SEED — T19 : Service CIDR multi-range (le candidat crée tout ; on nettoie)
echo "🌱 Seed T19 (Service CIDR multi-range)…"
kubectl create ns project-range >/dev/null 2>&1 || true
# supprimer d'abord les Services (libère les IPAddress) avant le ServiceCIDR
kubectl -n project-range delete svc range-svc range-svc2 --now >/dev/null 2>&1 || true
kubectl -n project-range delete pod range-probe --now >/dev/null 2>&1 || true
kubectl delete servicecidr extra-range --now >/dev/null 2>&1 || true

# Tout /opt/exam-03 doit rester inscriptible par le candidat.
sudo chmod -R 0777 "$BASE"

echo "✅ Setup exam-03 terminé."
echo "   Tâches disponibles : voir EXAM.md. Correction : bash /vagrant/mock-exam/exam-03/grade.sh"
