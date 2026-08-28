#!/usr/bin/env bash
# setup.sh — prépare le lab thématique « Services · Ingress · Gateway API ».
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/setup.sh"
#
# Idempotent : nettoie d'abord l'état précédent (namespaces + objets cluster),
# puis re-sème l'état de départ. NE contient AUCUNE solution.
set -uo pipefail

BASE=/opt/sig-lab
AGN=registry.k8s.io/e2e-test-images/agnhost:2.53

echo "🧹 Nettoyage de l'état précédent (idempotent)…"
kubectl delete ns services-lab ingress-lab gateway-lab --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ingressclass lab-nginx --ignore-not-found >/dev/null 2>&1 || true
kubectl delete gatewayclass lab-gwc --ignore-not-found >/dev/null 2>&1 || true
kubectl wait --for=delete ns/services-lab ns/ingress-lab ns/gateway-lab --timeout=120s >/dev/null 2>&1 || true
sudo rm -rf "$BASE"; sudo mkdir -p "$BASE"; sudo chmod 0777 "$BASE"

# ──────────────────────────────────────────────────────────────────────────────
# CRD Gateway API (installées une seule fois si absentes — canal « standard »)
if ! kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
  echo "🌐 Installation des CRD Gateway API (standard channel)…"
  GWAPI_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest \
    | grep -oP '"tag_name": "\K[^"]+')
  [ -n "${GWAPI_VER:-}" ] || GWAPI_VER=v1.2.1
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VER}/standard-install.yaml" >/dev/null 2>&1
fi

# ──────────────────────────────────────────────────────────────────────────────
kubectl create ns services-lab >/dev/null 2>&1
kubectl create ns ingress-lab  >/dev/null 2>&1
kubectl create ns gateway-lab  >/dev/null 2>&1

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE A — Services
#   web   (A1/A2) : Deployment 2 replicas, à exposer en ClusterIP puis NodePort.
#   cache (A3)    : Deployment 2 replicas, à exposer en Service headless.
#   shop  (A5)    : Deployment 2 replicas + Service CASSÉ (mauvais selector + targetPort).
#   legacy-db (A4): Pod « externe » (agnhost) — cible d'un Service SANS selector.
#   probe         : Pod agnhost pour les tests de connectivité du grader.
echo "🌱 Seed A (Services)…"
kubectl -n services-lab apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      containers:
      - name: cache
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shop
  template:
    metadata:
      labels:
        app: shop
    spec:
      containers:
      - name: shop
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
# Service CASSÉ pour A5 : selector erroné (app=shop-frontend) ET targetPort erroné (8080).
apiVersion: v1
kind: Service
metadata:
  name: shop-svc
spec:
  selector:
    app: shop-frontend
  ports:
  - port: 80
    targetPort: 8080
EOF

# legacy-db : écouteur TCP sur 5432 (cible des Endpoints manuels de A4)
kubectl -n services-lab run legacy-db --image="$AGN" --labels=app=legacy-db \
  --command -- /agnhost netexec --http-port=5432 >/dev/null 2>&1
# probe : client agnhost (le grader y lance `/agnhost connect`)
kubectl -n services-lab run probe --image="$AGN" --command -- /agnhost pause >/dev/null 2>&1
kubectl -n services-lab wait --for=condition=Ready pod --all --timeout=120s >/dev/null 2>&1 || true

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE B — Ingress
#   IngressClass lab-nginx (aucun contrôleur installé : on note l'OBJET Ingress).
#   echo : backends partagés ; web-svc / app-svc / api-svc pointent dessus.
echo "🌱 Seed B (Ingress)…"
kubectl -n ingress-lab apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: lab-nginx
spec:
  controller: k8s.io/ingress-nginx
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
      - name: echo
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  selector:
    app: echo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-svc
spec:
  selector:
    app: echo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api-svc
spec:
  selector:
    app: echo
  ports:
  - port: 80
    targetPort: 80
EOF

# ══════════════════════════════════════════════════════════════════════════════
# DOMAINE C — Gateway API
#   GatewayClass lab-gwc + Gateway edge (listener HTTP:80). Aucun contrôleur :
#   on note l'OBJET HTTPRoute. Backends echo partagés.
echo "🌱 Seed C (Gateway API)…"
kubectl -n gateway-lab apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: lab-gwc
spec:
  controllerName: example.com/lab-gateway
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge
  namespace: gateway-lab
spec:
  gatewayClassName: lab-gwc
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
      - name: echo
        image: nginx:1.29-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
spec:
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Service
metadata:
  name: api-svc
spec:
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Service
metadata:
  name: gold-svc
spec:
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Service
metadata:
  name: std-svc
spec:
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Service
metadata:
  name: canary-v1
spec:
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: v1
kind: Service
metadata:
  name: canary-v2
spec:
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 80 }]
EOF

sudo chmod -R 0777 "$BASE"
echo "✅ Setup lab Services/Ingress/Gateway terminé."
echo "   Tâches : voir LAB.md. Correction : bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"
