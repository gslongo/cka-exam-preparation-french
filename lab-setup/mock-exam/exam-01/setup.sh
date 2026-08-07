#!/usr/bin/env bash
# setup.sh — prépare l'environnement de l'examen blanc CKA sur le cluster du lab.
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"
#
# Idempotent : nettoie d'abord l'état précédent (réponses + seeds), puis re-sème
# les ressources « cassées » nécessaires aux exercices de troubleshooting.
# NE contient AUCUNE solution : seulement l'état de départ.
set -uo pipefail

GOOD_IMG="nginx:1.29-alpine"     # image valide
BAD_IMG="nginx:1.29-nope"        # tag inexistant (exo image cassée)
BUSYBOX="busybox:1.36"

echo "🧹 Nettoyage de l'état précédent (idempotent)…"
kubectl delete ns rbac-test workloads netpol storage trouble --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete pv pv-manual --ignore-not-found >/dev/null 2>&1
kubectl label node w1 disktype- >/dev/null 2>&1 || true
kubectl uncordon w1 w2 >/dev/null 2>&1 || true
sudo rm -f /opt/etcd-backup.db 2>/dev/null || true

# Attendre la vraie disparition des namespaces (finalizers) avant recréation
for ns in rbac-test workloads netpol storage trouble; do
  kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true
done

echo "📦 etcd-client (pour l'exo snapshot)…"
if ! command -v etcdctl >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y etcd-client >/dev/null 2>&1 \
    && echo "   etcdctl installé" || echo "   ⚠️ install etcd-client KO (réseau ?) — l'exo etcd reste faisable via le pod etcd"
fi

echo "🌱 Création des namespaces…"
for ns in rbac-test workloads netpol storage trouble; do
  # retry tant que l'ancien ns est encore Terminating (create échoue sinon)
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns indisponible (toujours Terminating ?)"; break; }
    sleep 2
  done
done

# ──────────────────────────────────────────────────────────────────────────────
# SEED — Services & Networking : NetworkPolicy (netpol)
#   backend (app=backend, écoute :80) + Service backend
#   frontend (app=frontend) et client (app=other) = testeurs
#   Aucune NetworkPolicy créée → tout est permis au départ (l'exo la demande)
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

# T13 — image cassée (ImagePullBackOff)
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

# T14 — Service avec mauvais selector (0 endpoint)
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
  selector: { app: apiv1 }          # BUG : aucun Pod ne porte ce label
  ports: [{ port: 80, targetPort: 80 }]
EOF

# T15 — Pod Pending (request mémoire délirante)
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

# T16 — Deployment bloqué : ConfigMap de volume manquante (CreateContainerConfigError)
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
        configMap: { name: cfg-app-config }   # BUG : cette ConfigMap n'existe pas
EOF

echo
echo "✅ Environnement d'examen prêt."
echo "   • Ouvre le sujet : lab-setup/mock-exam/exam-01/EXAM.md"
echo "   • Chrono conseillé : 2 h."
echo "   • Correction à la fin : bash /vagrant/mock-exam/exam-01/grade.sh"
