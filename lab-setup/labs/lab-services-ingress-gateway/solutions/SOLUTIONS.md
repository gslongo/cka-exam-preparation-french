# ✅ Lab — Services · Ingress · Gateway API · SOLUTIONS

> **Only open this file after your attempt.** Each solution matches exactly the criteria of `grade.sh`.
> All commands are to be run from `cp1` (`vagrant ssh cp1`).

---

## 🔌 Domain A — Services

### A1 — Expose a Deployment as ClusterIP
```bash
kubectl -n services-lab expose deployment web \
  --name web-svc --port 80 --target-port 80        # ClusterIP type by default

# Verify
kubectl -n services-lab get svc web-svc
kubectl -n services-lab get endpoints web-svc       # 2 IP:80
```
> Key points: `expose` reuses the Deployment's selector (`app=web`). If the endpoints stay empty, it's almost always a **selector** or a **targetPort** that doesn't match.

### A2 — NodePort with a fixed port
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
> Key points: without `nodePort`, Kubernetes picks one from `30000-32767`. To **force** `30080`, you set it explicitly (`kubectl expose` doesn't allow it directly).

### A3 — Headless Service
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

kubectl -n services-lab get endpoints cache-hl   # the 2 cache Pod IPs
```
> Key points: `clusterIP: None` ⇒ no virtual IP, no kube-proxy load balancing. DNS (`cache-hl.services-lab.svc`) returns **all the A records** of the Pods (typical StatefulSet use case).

### A4 — Service without selector + manual Endpoints
```bash
# 1) IP of the "external" Pod
IP=$(kubectl -n services-lab get pod legacy-db -o jsonpath='{.status.podIP}')
echo "$IP"

# 2) Service WITHOUT selector + Endpoints carrying the same name
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
  name: db-ext            # ← SAME name as the Service
subsets:
- addresses:
  - ip: ${IP}
  ports:
  - port: 5432
EOF

# Verify: the clusterIP does route through to legacy-db
CIP=$(kubectl -n services-lab get svc db-ext -o jsonpath='{.spec.clusterIP}')
kubectl -n services-lab exec probe -- /agnhost connect "$CIP:5432" --timeout=3s && echo OK
```
> Key points: a Service **without a selector** generates **no** Endpoints → you create it by hand, with the **same name** as the Service. This is the pattern for pointing to an out-of-cluster resource (managed DB, fixed IP…). ⚠️ `kubectl` prints "v1 Endpoints is deprecated": the `Endpoints` object stays **functional** (mirrored to `EndpointSlice`); the modern alternative is to create an `EndpointSlice` directly (`discovery.k8s.io/v1`).

### A5 — Fix a broken Service
```bash
# Diagnostic: empty endpoints
kubectl -n services-lab get endpoints shop-svc
kubectl -n services-lab get pods -l app=shop --show-labels   # real port = 80, label = app=shop
kubectl -n services-lab get svc shop-svc -o yaml | grep -A6 spec:

# Fix: selector app=shop  +  targetPort 80
kubectl -n services-lab patch svc shop-svc --type merge -p \
  '{"spec":{"selector":{"app":"shop"},"ports":[{"port":80,"targetPort":80}]}}'

# Verify
kubectl -n services-lab get endpoints shop-svc               # populated
```
> Key points: two combined errors — the **selector** (`app=shop-frontend` instead of `app=shop`) and the **targetPort** (`8080` instead of `80`). The endpoints only populate if the selector matches **ready** Pods and the `targetPort` is a real port.

---

## 🌐 Domain B — Ingress

### B1 — Simple Ingress (host + path)
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
> Key points: `ingressClassName` designates the target controller. `pathType: Prefix` (≠ `Exact`). Backend = `service.name` + `port.number`.

### B2 — "Fanout" Ingress
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
> Key points: a single `host`, several `paths` → L7 routing by path prefix to different Services.

### B3 — Ingress TLS
```bash
# 1) Self-signed certificate + TLS Secret
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout tls.key -out tls.crt -subj "/CN=secure.cka.local"
kubectl -n ingress-lab create secret tls secure-tls --cert=tls.crt --key=tls.key

# 2) Ingress with tls block
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
> Key points: the Secret must be of type `kubernetes.io/tls` (keys `tls.crt`/`tls.key`) → `kubectl create secret tls`. The `spec.tls` block associates the **host** with the **secretName**; the `tls` host must match the one in the rule.

---

## 🚪 Domain C — Gateway API

### C1 — HTTPRoute: prefix routing
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
> Key points: `parentRefs` attaches the route to the Gateway `edge`. The Gateway API `pathType` is called `PathPrefix` (≠ Ingress `Prefix`).

### C2 — HTTPRoute: header + catch-all
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
  - matches:                       # /shop AND X-Tier: gold (same match = AND)
    - path: { type: PathPrefix, value: /shop }
      headers:
      - { name: X-Tier, value: gold }
    backendRefs:
    - { name: gold-svc, port: 80 }
  - matches:                       # catch-all /shop (AFTER the specific rule)
    - path: { type: PathPrefix, value: /shop }
    backendRefs:
    - { name: std-svc, port: 80 }
EOF
```
> Key points: `path` **+** `headers` in the **same** match = **logical AND**. **Order matters**: the specific rule (with the header) must precede the catch-all, otherwise all `/shop` goes to `std-svc`.

### C3 — HTTPRoute: weighted split (canary)
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
> Key points: **several** `backendRefs` in **one** rule, each with a `weight`. The proportion is `weight / Σ weights` (90 % vs 10 %) — the pattern for *canary* / *blue-green* deployment with Gateway API.

---

> 💡 Reminder: here no controller actually enforces Ingress/Gateway — we validate the **declaration**.
> In production, a controller (ingress-nginx, Envoy Gateway, Cilium…) would materialize these objects into real routing.
