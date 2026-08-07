#!/usr/bin/env bash
# setup.sh — prépare l'examen blanc CKA n°2 (niveau avancé) sur le cluster du lab.
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/setup.sh"
#
# Idempotent : nettoie d'abord l'état précédent (réponses + seeds), puis re-sème
# les ressources « cassées » nécessaires aux exercices de troubleshooting.
# NE contient AUCUNE solution : seulement l'état de départ.
# Aucun « vagrant destroy » nécessaire : tout se joue au niveau des objets K8s.
set -uo pipefail

GOOD_IMG="nginx:1.29-alpine"     # image valide
BUSYBOX="busybox:1.36"

echo "🧹 Nettoyage de l'état précédent (idempotent)…"
kubectl delete ns platform apps secure storage trouble --ignore-not-found --wait=false >/dev/null 2>&1
kubectl delete clusterrole deploy-admin --ignore-not-found >/dev/null 2>&1
kubectl delete clusterrolebinding ci-bot-deploy --ignore-not-found >/dev/null 2>&1
kubectl delete pv pv-fast --ignore-not-found >/dev/null 2>&1
kubectl taint node w1 dedicated- >/dev/null 2>&1 || true
kubectl label node w1 disktype- >/dev/null 2>&1 || true
kubectl label node w2 disktype- >/dev/null 2>&1 || true
kubectl uncordon w1 w2 >/dev/null 2>&1 || true
sudo rm -f /opt/etcd-backup.db 2>/dev/null || true

# Attendre la vraie disparition des namespaces (finalizers) avant recréation
for ns in platform apps secure storage trouble; do
  kubectl wait --for=delete ns/$ns --timeout=120s >/dev/null 2>&1 || true
done

echo "📦 etcd-client (pour l'exo snapshot)…"
if ! command -v etcdctl >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y etcd-client >/dev/null 2>&1 \
    && echo "   etcdctl installé" || echo "   ⚠️ install etcd-client KO (réseau ?) — l'exo etcd reste faisable via le pod etcd"
fi

echo "🌱 Création des namespaces…"
for ns in platform apps secure storage trouble; do
  # retry tant que l'ancien ns est encore Terminating (create échoue sinon)
  tries=0
  until kubectl create ns "$ns" >/dev/null 2>&1; do
    tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "   ⚠️ ns $ns indisponible (toujours Terminating ?)"; break; }
    sleep 2
  done
done

# ──────────────────────────────────────────────────────────────────────────────
# SEED — Services & Networking : NetworkPolicy default-deny (secure)
#   db (app=db, écoute :80) + Service db ; web (app=web) et scanner (app=other)
#   Aucune NetworkPolicy créée → tout est permis au départ (l'exo demande de fermer)
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

# T13 — readinessProbe cassée (pods jamais Ready → 0 disponible)
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
          httpGet: { path: /, port: 8080 }   # BUG : nginx écoute 80, pas 8080
          initialDelaySeconds: 3
          periodSeconds: 5
EOF

# T14 — Service sans endpoints (selector ≠ labels des pods)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: store, namespace: trouble }
spec:
  replicas: 2
  selector: { matchLabels: { app: store-v2 } }
  template:
    metadata: { labels: { app: store-v2 } }   # les pods portent app=store-v2
    spec:
      containers:
      - { name: web, image: ${GOOD_IMG}, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: store-svc, namespace: trouble }
spec:
  selector: { app: store }          # BUG : aucun pod ne porte app=store
  ports: [{ port: 80, targetPort: 80 }]
EOF

# T15 — Pod Pending (contrainte de placement impossible)
kubectl -n trouble apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: stuck, namespace: trouble }
spec:
  nodeSelector: { disktype: nvme }   # BUG : aucun node n'a ce label
  containers:
  - { name: web, image: ${GOOD_IMG} }
EOF

# T16 — Deployment bloqué : Secret d'env manquant (CreateContainerConfigError)
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
            secretKeyRef: { name: billing-secret, key: API_KEY }   # BUG : ce Secret n'existe pas
EOF

echo
echo "✅ Environnement d'examen n°2 prêt."
echo "   • Ouvre le sujet : lab-setup/mock-exam/exam-02/EXAM.md"
echo "   • Chrono conseillé : 2 h."
echo "   • Correction à la fin : bash /vagrant/mock-exam/exam-02/grade.sh"
