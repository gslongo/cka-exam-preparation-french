# ✅ Lab — Services · Ingress · Gateway API · SOLUTIONS

> **N'ouvre ce fichier qu'après ta tentative.** Chaque solution correspond exactement aux critères de `grade.sh`.
> Toutes les commandes sont à lancer depuis `cp1` (`vagrant ssh cp1`).

---

## 🔌 Domaine A — Services

### A1 — Exposer un Deployment en ClusterIP
```bash
kubectl -n services-lab expose deployment web \
  --name web-svc --port 80 --target-port 80        # type ClusterIP par défaut

# Vérif
kubectl -n services-lab get svc web-svc
kubectl -n services-lab get endpoints web-svc       # 2 IP:80
```
> Points clés : `expose` reprend le selector du Deployment (`app=web`). Si les endpoints restent vides, c'est presque toujours un **selector** ou un **targetPort** qui ne correspond pas.

### A2 — NodePort avec un port fixe
```bash
kubectl -n services-lab apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-np
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
EOF
```
> Points clés : sans `nodePort`, Kubernetes en choisit un dans `30000-32767`. Pour **imposer** `30080`, on le fixe explicitement (`kubectl expose` ne le permet pas directement).

### A3 — Service headless
```bash
kubectl -n services-lab apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: cache-hl
spec:
  clusterIP: None          # ← headless
  selector:
    app: cache
  ports:
  - port: 80
    targetPort: 80
EOF

kubectl -n services-lab get endpoints cache-hl   # les 2 IP des Pods cache
```
> Points clés : `clusterIP: None` ⇒ pas d'IP virtuelle, pas d'équilibrage kube-proxy. Le DNS (`cache-hl.services-lab.svc`) renvoie **tous les A records** des Pods (usage typique des StatefulSets).

### A4 — Service sans selector + Endpoints manuels
```bash
# 1) IP du Pod « externe »
IP=$(kubectl -n services-lab get pod legacy-db -o jsonpath='{.status.podIP}')
echo "$IP"

# 2) Service SANS selector + Endpoints portant le même nom
kubectl -n services-lab apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: db-ext
spec:
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: v1
kind: Endpoints
metadata:
  name: db-ext            # ← MÊME nom que le Service
subsets:
- addresses:
  - ip: ${IP}
  ports:
  - port: 5432
EOF

# Vérif : le clusterIP route bien jusqu'à legacy-db
CIP=$(kubectl -n services-lab get svc db-ext -o jsonpath='{.spec.clusterIP}')
kubectl -n services-lab exec probe -- /agnhost connect "$CIP:5432" --timeout=3s && echo OK
```
> Points clés : un Service **sans selector** ne génère **aucun** Endpoints → on le crée à la main, avec le **même nom** que le Service. C'est le patron pour pointer vers une ressource hors cluster (BDD managée, IP fixe…). ⚠️ `kubectl` affiche « v1 Endpoints is deprecated » : l'objet `Endpoints` reste **fonctionnel** (mirroré en `EndpointSlice`) ; l'alternative moderne est de créer directement un `EndpointSlice` (`discovery.k8s.io/v1`).

### A5 — Réparer un Service cassé
```bash
# Diagnostic : endpoints vides
kubectl -n services-lab get endpoints shop-svc
kubectl -n services-lab get pods -l app=shop --show-labels   # port réel = 80, label = app=shop
kubectl -n services-lab get svc shop-svc -o yaml | grep -A6 spec:

# Correction : selector app=shop  +  targetPort 80
kubectl -n services-lab patch svc shop-svc --type merge -p \
  '{"spec":{"selector":{"app":"shop"},"ports":[{"port":80,"targetPort":80}]}}'

# Vérif
kubectl -n services-lab get endpoints shop-svc               # peuplé
```
> Points clés : deux erreurs cumulées — le **selector** (`app=shop-frontend` au lieu de `app=shop`) et le **targetPort** (`8080` au lieu de `80`). Les endpoints ne se peuplent que si le selector matche des Pods **prêts** et que le `targetPort` est un port réel.

---

## 🌐 Domaine B — Ingress

### B1 — Ingress simple (hôte + chemin)
```bash
kubectl -n ingress-lab apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: site
spec:
  ingressClassName: lab-nginx
  rules:
  - host: web.cka.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
EOF
```
> Points clés : `ingressClassName` désigne le contrôleur cible. `pathType: Prefix` (≠ `Exact`). Backend = `service.name` + `port.number`.

### B2 — Ingress « fanout »
```bash
kubectl -n ingress-lab apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps
spec:
  ingressClassName: lab-nginx
  rules:
  - host: apps.cka.local
    http:
      paths:
      - path: /app
        pathType: Prefix
        backend:
          service: { name: app-svc, port: { number: 80 } }
      - path: /api
        pathType: Prefix
        backend:
          service: { name: api-svc, port: { number: 80 } }
EOF
```
> Points clés : un seul `host`, plusieurs `paths` → routage L7 par préfixe de chemin vers des Services différents.

### B3 — Ingress TLS
```bash
# 1) Certificat auto-signé + Secret TLS
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout tls.key -out tls.crt -subj "/CN=secure.cka.local"
kubectl -n ingress-lab create secret tls secure-tls --cert=tls.crt --key=tls.key

# 2) Ingress avec bloc tls
kubectl -n ingress-lab apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure
spec:
  ingressClassName: lab-nginx
  tls:
  - hosts:
    - secure.cka.local
    secretName: secure-tls
  rules:
  - host: secure.cka.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: { name: web-svc, port: { number: 80 } }
EOF
```
> Points clés : le Secret doit être de type `kubernetes.io/tls` (clés `tls.crt`/`tls.key`) → `kubectl create secret tls`. Le bloc `spec.tls` associe l'**hôte** au **secretName** ; l'hôte du `tls` doit correspondre à celui de la règle.

---

## 🚪 Domaine C — Gateway API

### C1 — HTTPRoute : routage par préfixe
```bash
kubectl -n gateway-lab apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: main-route
spec:
  parentRefs:
  - name: edge
  rules:
  - matches:
    - path: { type: PathPrefix, value: /web }
    backendRefs:
    - { name: web-svc, port: 80 }
  - matches:
    - path: { type: PathPrefix, value: /api }
    backendRefs:
    - { name: api-svc, port: 80 }
EOF
```
> Points clés : `parentRefs` rattache la route au Gateway `edge`. Le `pathType` de Gateway API s'appelle `PathPrefix` (≠ Ingress `Prefix`).

### C2 — HTTPRoute : en-tête + catch-all
```bash
kubectl -n gateway-lab apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tier-route
spec:
  parentRefs:
  - name: edge
  rules:
  - matches:                       # /shop ET X-Tier: gold (même match = ET)
    - path: { type: PathPrefix, value: /shop }
      headers:
      - { name: X-Tier, value: gold }
    backendRefs:
    - { name: gold-svc, port: 80 }
  - matches:                       # catch-all /shop (APRÈS la règle spécifique)
    - path: { type: PathPrefix, value: /shop }
    backendRefs:
    - { name: std-svc, port: 80 }
EOF
```
> Points clés : `path` **+** `headers` dans le **même** match = **ET logique**. **L'ordre compte** : la règle spécifique (avec en-tête) doit précéder le catch-all, sinon tout `/shop` part vers `std-svc`.

### C3 — HTTPRoute : répartition pondérée (canary)
```bash
kubectl -n gateway-lab apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary-route
spec:
  parentRefs:
  - name: edge
  rules:
  - matches:
    - path: { type: PathPrefix, value: / }
    backendRefs:
    - { name: canary-v1, port: 80, weight: 90 }
    - { name: canary-v2, port: 80, weight: 10 }
EOF
```
> Points clés : **plusieurs** `backendRefs` dans **une** règle, chacun avec un `weight`. La proportion est `weight / Σ weights` (90 % vs 10 %) — le patron du déploiement *canary* / *blue-green* avec Gateway API.

---

> 💡 Rappel : ici aucun contrôleur n'applique réellement Ingress/Gateway — on valide la **déclaration**.
> En production, un contrôleur (ingress-nginx, Envoy Gateway, Cilium…) matérialiserait ces objets en routage réel.
