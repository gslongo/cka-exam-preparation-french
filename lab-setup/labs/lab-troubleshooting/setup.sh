#!/usr/bin/env bash
# setup.sh — prépare le lab thématique « Troubleshooting transverse (tous domaines) ».
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/setup.sh"
#
# Principe : TOUT est cassé au départ. Le candidat doit RÉPARER (voir LAB.md).
# Idempotent : nettoie d'abord l'état précédent (y compris les réparations d'un run
# précédent : noeuds cordonnés/taintés, manifest statique sur cp1, finalizers bloqués),
# puis re-sème l'état « cassé ». NE contient AUCUNE solution.
set -uo pipefail

GOOD_IMG="nginx:1.29-alpine"     # image valide
BAD_IMG="nginx:1.29-nope"        # tag inexistant (ImagePullBackOff)
BUSYBOX="busybox:1.36"
NSES="ts-arch ts-nodes ts-work ts-net ts-netpol ts-storage"
STATIC_MANIFEST="/etc/kubernetes/manifests/ts-static.yaml"

echo "🧹 Nettoyage de l'état précédent (idempotent)…"

# 0) Débloquer un éventuel ConfigMap coincé en Terminating (finalizer) d'un run précédent,
#    sinon la suppression du namespace ts-arch resterait bloquée.
kubectl -n ts-arch patch cm stuck-cm --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true

# 1) Retirer le static pod cassé posé sur cp1 (le kubelet supprimera le mirror pod).
sudo rm -f "$STATIC_MANIFEST" 2>/dev/null || true

# 2) Réinitialiser l'état des noeuds (au cas où un run précédent aurait été réparé/laissé en l'état).
kubectl uncordon w1 w2 >/dev/null 2>&1 || true
kubectl taint node w1 maintenance- >/dev/null 2>&1 || true
kubectl label node w1 role- >/dev/null 2>&1 || true
kubectl label node w1 w2 cp1 disktype- >/dev/null 2>&1 || true

# 3) Supprimer namespaces + PV (cluster-scoped), puis attendre la disparition réelle.
kubectl delete ns $NSES --ignore-not-found >/dev/null 2>&1 || true
kubectl delete pv pv-small pv-app --ignore-not-found >/dev/null 2>&1 || true
for ns in $NSES; do
  kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true
done
kubectl wait --for=delete pv/pv-small pv/pv-app --timeout=60s >/dev/null 2>&1 || true

echo "🌱 Recréation des namespaces…"
for ns in $NSES; do
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns indisponible (Terminating ?)"; break; }
    sleep 2
  done
done

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE ARCH — Cluster Architecture & Nodes
# ══════════════════════════════════════════════════════════════════════════════

# A1 — RBAC cassé : la RoleBinding vise un mauvais sujet (typo) → deploy-bot n'a aucun droit.
echo "🌱 A1 (RBAC cassé)…"
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
  name: deploy-bot-typo          # BUG : ce ServiceAccount n'existe pas (le bon est deploy-bot)
  namespace: ts-arch
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# A4 — ConfigMap coincée en Terminating (finalizer non résolu).
echo "🌱 A4 (objet coincé Terminating)…"
kubectl -n ts-arch apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: stuck-cm
  namespace: ts-arch
  finalizers: ["example.com/hold"]   # BUG : aucun controller ne retire ce finalizer
data: { note: "supprime-moi proprement" }
EOF
kubectl -n ts-arch delete cm stuck-cm --wait=false >/dev/null 2>&1 || true

# A2 — Static pod cassé sur cp1 (mauvais tag d'image → ImagePullBackOff).
echo "🌱 A2 (static pod cassé sur cp1)…"
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
    image: ${BAD_IMG}          # BUG : tag inexistant
    ports: [{ containerPort: 80 }]
EOF

# A3 — Noeud w1 « hors service » : cordonné + taint NoSchedule, avec un Deployment épinglé dessus.
echo "🌱 A3 (noeud w1 hors service)…"
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
      nodeSelector: { role: billing }   # forcé sur w1 (seul noeud labelisé) → bloqué par cordon + taint
      containers:
      - { name: web, image: ${GOOD_IMG} }
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE WORK — Workloads & Scheduling
# ══════════════════════════════════════════════════════════════════════════════

# W1 — ImagePullBackOff (Deployment, image à corriger).
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
      - { name: web, image: ${BAD_IMG} }   # BUG : tag inexistant
EOF

# W2 — CrashLoopBackOff (commande qui sort en erreur).
echo "🌱 W2 (CrashLoopBackOff)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: crasher, namespace: ts-work, labels: { app: crasher } }
spec:
  containers:
  - name: c
    image: ${BUSYBOX}
    command: ["sh","-c","echo demarrage; exit 1"]   # BUG : sort aussitôt en erreur
EOF

# W3 — CreateContainerConfigError (clé de Secret manquante).
echo "🌱 W3 (clé de Secret manquante)…"
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
        secretKeyRef: { name: app-secret, key: password }   # BUG : la clé 'password' n'existe pas
EOF

# W4 — Pending (request mémoire délirante).
echo "🌱 W4 (Pending — requests)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: report, namespace: ts-work, labels: { app: report } }
spec:
  containers:
  - name: c
    image: ${GOOD_IMG}
    resources: { requests: { memory: "100Gi", cpu: "40" } }   # BUG : inschedulable
EOF

# W5 — Pending (nodeSelector qui ne matche aucun noeud).
echo "🌱 W5 (Pending — nodeSelector)…"
kubectl -n ts-work apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: analytics, namespace: ts-work, labels: { app: analytics } }
spec:
  nodeSelector: { disktype: ssd }   # BUG : aucun noeud ne porte ce label
  containers:
  - { name: c, image: ${GOOD_IMG} }
EOF

# W6 — Readiness probe erronée (pods Running mais jamais Ready).
echo "🌱 W6 (readiness KO)…"
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
          httpGet: { path: /, port: 8080 }   # BUG : nginx écoute sur 80, pas 8080
          periodSeconds: 5
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE NET — Services & Networking
# ══════════════════════════════════════════════════════════════════════════════

# N1 — Service sans endpoints (selector qui ne matche pas).
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
  selector: { app: api-v1 }          # BUG : aucun Pod ne porte ce label
  ports: [{ port: 80, targetPort: 80 }]
EOF

# N2 — Service avec mauvais targetPort (endpoints présents mais trafic KO).
echo "🌱 N2 (targetPort erroné)…"
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
  ports: [{ port: 80, targetPort: 8080 }]   # BUG : le conteneur écoute sur 80
---
apiVersion: v1
kind: Pod
metadata: { name: shop-client, namespace: ts-net, labels: { app: shop-client } }
spec:
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# N4 — DNS : Pod avec dnsPolicy Default (ne résout pas les services du cluster).
echo "🌱 N4 (dnsPolicy Default)…"
kubectl -n ts-net apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: { name: dns-broken, namespace: ts-net, labels: { app: dns-broken } }
spec:
  dnsPolicy: Default                 # BUG : n'utilise pas CoreDNS → pas de résolution *.svc.cluster.local
  containers:
  - { name: c, image: ${BUSYBOX}, command: ["sh","-c","sleep 100000"] }
EOF

# N3 — NetworkPolicy default-deny qui bloque un trafic légitime (namespace dédié).
echo "🌱 N3 (NetworkPolicy bloquante)…"
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
  podSelector: {}                    # BUG : bloque TOUTE entrée, y compris client → backend
  policyTypes: ["Ingress"]
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE STO — Storage
# ══════════════════════════════════════════════════════════════════════════════

# S1 — PVC Pending (storageClassName qui ne correspond à aucun PV).
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
  storageClassName: fast            # BUG : aucun PV (ni provisioner) en classe 'fast'
  resources: { requests: { storage: 3Gi } }
EOF

# S2 — Pod bloqué : la PVC référencée n'existe pas.
echo "🌱 S2 (PVC manquante)…"
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
    persistentVolumeClaim: { claimName: app-pvc }   # BUG : la PVC 'app-pvc' n'existe pas
EOF

echo
echo "✅ Environnement de troubleshooting prêt — TOUT est cassé, à toi de réparer."
echo "   • Sujet     : lab-setup/labs/lab-troubleshooting/LAB.md"
echo "   • Correction: bash /vagrant/labs/lab-troubleshooting/grade.sh"
echo "   • État des noeuds :"
kubectl get nodes -o custom-columns=NODE:.metadata.name,STATUS:.status.conditions[-1].type,SCHED:.spec.unschedulable,TAINTS:.spec.taints[*].key 2>/dev/null
