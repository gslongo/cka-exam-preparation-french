# 🌐 Lab — Services · Ingress · Gateway API

> **Themed lab** (not a mock exam): it focuses on **traffic exposure**
> across three layers — *Services* (L4), *Ingress* (L7 "legacy"), *Gateway API* (L7 modern).
> The tasks are **independent** and of increasing difficulty: you can do just one at a time.
> **100 pts**, target **≥ 75 %**. No time limit — this is a practice lab. **Estimated time: ~1 h – 1 h 30** (11 tasks).

> ⚠️ **No Ingress or Gateway controller is installed** (as is often the case in the CKA): for these two
> layers, the grader **grades the Kubernetes object** (correct declaration: class, hosts, paths,
> backends, headers, weights…), not real traffic. For the **Services**, connectivity is
> **tested live** (a `probe` Pod connects to the ClusterIPs).

## Getting started
```bash
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/setup.sh"   # seed the starting state
# … solve the tasks …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"   # grade yourself (read-only)
```
> `setup.sh` is **idempotent**: it re-creates the `services-lab`, `ingress-lab`, `gateway-lab` namespaces
> and (if needed) installs the **Gateway API** CRDs. It cleans up your previous answers before re-seeding.
> The solutions are in [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — open it only afterwards.

---

## 🔌 Domain A — Services (40 pts) · Namespace `services-lab`

### A1 — Expose a Deployment as ClusterIP (10 pts)
A *Deployment* `web` (2 replicas, `app=web`, container on port **80**) is already running.
Create a **ClusterIP** *Service* named `web-svc` that exposes it on port **80 → 80**.

> 💡 `kubectl expose deployment web --name web-svc --port 80 --target-port 80` (ClusterIP type by default). Verify that the *endpoints* get populated: `kubectl -n services-lab get endpoints web-svc`.
> Expected: `web-svc` of type `ClusterIP`, port `80→80`, selector `app=web`, **2 endpoints** ready and reachable on `:80`.

### A2 — Expose the same Deployment as NodePort (8 pts)
Also expose `web` with a second *Service* named `web-np` of type **NodePort**, port **80 → 80**,
fixing the **nodePort** to **`30080`**.

> 💡 `kubectl expose … --type NodePort …` assigns a random nodePort; to **force** `30080`, edit the Service (or start from a YAML with `spec.ports[0].nodePort: 30080`).
> Expected: `web-np` of type `NodePort`, `nodePort=30080`, port `80→80`, selector `app=web`.

### A3 — Headless Service for a set of Pods (8 pts)
A *Deployment* `cache` (2 replicas, `app=cache`) is running. Create a **headless** *Service* named
`cache-hl` (**without** a cluster IP) on port **80**, selecting those Pods.

> 💡 A *headless* Service is declared with `spec.clusterIP: None`. It does no load balancing: DNS returns **the Pod IPs directly**. Verify: `kubectl -n services-lab get endpoints cache-hl` (both IPs must appear).
> Expected: `cache-hl` with `clusterIP: None`, selector `app=cache`, port `80`, **2 endpoint addresses**.

### A4 — Service without selector + manual Endpoints (8 pts)
A Pod `legacy-db` (label `app=legacy-db`) listens on port **5432** — imagine an "external" database
you want to reach through a stable Service name. Create:

1. a **ClusterIP** *Service* `db-ext` **without a selector**, port **5432 → 5432**;
2. an **Endpoints** object `db-ext` (same name as the Service) pointing to the **IP of the `legacy-db` Pod** on port **5432**.

> 💡 Get the IP: `kubectl -n services-lab get pod legacy-db -o wide` (`IP` column). A Service without a selector **does not create** Endpoints automatically → you must create the `Endpoints` object by hand (same name as the Service). An `EndpointSlice` name works too, but the classic `Endpoints` is the fastest.
> Expected: `db-ext` **without** a selector (port 5432), an `Endpoints db-ext` with ≥1 address, and the connection `clusterIP:5432` does reach `legacy-db`.

### A5 — Fix a broken Service (6 pts)
The *Service* `shop-svc` is meant to expose the *Deployment* `shop` (2 replicas, `app=shop`, port **80**),
but **no endpoint** shows up. Diagnose and **fix** the Service (do not delete it).

> 💡 `kubectl -n services-lab get endpoints shop-svc` returns empty ⇒ the Service "matches" no ready Pod. Compare the Service's `spec.selector` and `targetPort` with the real labels/port of the `shop` Pods (`kubectl -n services-lab get pods --show-labels`). Fix it with `kubectl edit svc shop-svc`.
> Expected: `shop-svc` has populated endpoints and responds on `:80`.

---

## 🌐 Domain B — Ingress (30 pts) · Namespace `ingress-lab`

> An *IngressClass* `lab-nginx` and three backend *Services* (`web-svc`, `app-svc`, `api-svc`, all
> ClusterIP:80) are already present. The grader **grades the Ingress objects** (no controller is installed).

### B1 — Simple Ingress, host + path (10 pts)
Create an *Ingress* named `site` (class `lab-nginx`) that routes the host **`web.cka.local`**,
path **`/`** of type **`Prefix`**, to the *Service* **`web-svc`** port **80**.

> 💡 `spec.ingressClassName: lab-nginx`. Each rule carries a `host`, and each path a `pathType` (`Prefix` here) + a `backend.service.name`/`port.number`. `kubectl create ingress` accepts the syntax `--rule="web.cka.local/*=web-svc:80"` (to be adjusted for the pathType).
> Expected: `site` — `ingressClassName=lab-nginx`, host `web.cka.local`, path `/` (Prefix) → `web-svc:80`.

### B2 — "Fanout" multi-path Ingress (10 pts)
Create an *Ingress* named `apps` (class `lab-nginx`) for the host **`apps.cka.local`** that splits by path:

- **`/app`** (Prefix) → *Service* **`app-svc`** port **80** ;
- **`/api`** (Prefix) → *Service* **`api-svc`** port **80**.

> 💡 A single `host`, two entries under `http.paths`, each with its `pathType: Prefix` and its backend. Order doesn't matter here (disjoint paths). Reflex: **always** set `ingressClassName` — without it (and without a default IngressClass), no controller adopts your Ingress.
> Expected: `apps` — `ingressClassName=lab-nginx`, host `apps.cka.local`, `/app`→`app-svc:80` and `/api`→`api-svc:80` (Prefix).

### B3 — Ingress with TLS (10 pts)
Secure a host with TLS:

1. Create a TLS *Secret* named **`secure-tls`** (type `kubernetes.io/tls`) — a self-signed certificate for **`secure.cka.local`** is enough.
2. Create an *Ingress* named `secure` (class `lab-nginx`) for the host **`secure.cka.local`**, with a **`tls`** block referencing `secure-tls`, and a rule path **`/`** → *Service* **`web-svc`** port **80**.

> 💡 Generate the pair with `openssl req -x509 -newkey rsa:2048 -nodes -keyout tls.key -out tls.crt -days 365 -subj "/CN=secure.cka.local"`, then `kubectl -n ingress-lab create secret tls secure-tls --cert=tls.crt --key=tls.key`. In the Ingress, `spec.tls: [{ hosts: [secure.cka.local], secretName: secure-tls }]`.
> Expected: Secret `secure-tls` (TLS type); Ingress `secure` with `ingressClassName=lab-nginx`, `tls.secretName=secure-tls`, `tls.hosts[0]=secure.cka.local`, rule host `secure.cka.local` `/`→`web-svc:80`.

---

## 🚪 Domain C — Gateway API (30 pts) · Namespace `gateway-lab`

> A *GatewayClass* `lab-gwc` and a *Gateway* `edge` (HTTP:80 listener) are already deployed, along with the
> backend *Services* (`web-svc`, `api-svc`, `gold-svc`, `std-svc`, `canary-v1`, `canary-v2`, all ClusterIP:80).
> You only create the **HTTPRoute** objects (`gateway.networking.k8s.io/v1`). The grader grades the objects.

### C1 — HTTPRoute: prefix routing (10 pts)
Create an *HTTPRoute* named `main-route`, attached to the *Gateway* **`edge`**, that routes:

- the prefix **`/web`** → *Service* **`web-svc`** port **80** ;
- the prefix **`/api`** → *Service* **`api-svc`** port **80**.

> 💡 `spec.parentRefs: [{ name: edge }]`. Each rule: `matches[].path` (`type: PathPrefix`, `value: /web`) and `backendRefs[]` (`name`, `port`). One rule per path.
> Expected: `main-route` references `edge`; `/web`→`web-svc:80` and `/api`→`api-svc:80`.

### C2 — HTTPRoute: header match + catch-all (10 pts)
Create an *HTTPRoute* named `tier-route`, attached to **`edge`**, for the prefix **`/shop`**:

- if the request carries the header **`X-Tier: gold`** → *Service* **`gold-svc`** port **80** (path **AND** header in the **same** *match*) ;
- **otherwise** (`/shop` alone, without the header) → *Service* **`std-svc`** port **80**.

> 💡 A `match` that lists both `path` **and** `headers` applies a **logical AND**. Put the `/shop` + header rule **before** the `/shop` catch-all: **rule order matters** (the first match wins). Split them into **two** separate rules (each with its `backendRefs`).
> Expected: `tier-route` — `/shop` + `X-Tier: gold` (same match) → `gold-svc` ; `/shop` alone → `std-svc`.

### C3 — HTTPRoute: weighted split (canary) (10 pts)
Create an *HTTPRoute* named `canary-route`, attached to **`edge`**, that sends the traffic of path **`/`**
to **two** backends with **weights**:

- **`canary-v1`** port **80**, weight **90** ;
- **`canary-v2`** port **80**, weight **10**.

> 💡 A single rule with **two** entries in `backendRefs`, each with its `weight` field. The split is proportional to the sum of the weights (here 90/100 and 10/100).
> Expected: `canary-route` (attached to `edge`) with `canary-v1` weight **90** and `canary-v2` weight **10** in the same rule.

---

_This lab is extensible: say "add a task on `<topic>`" (e.g. `ExternalName`, `sessionAffinity`, cross-namespace `ReferenceGrant`, multi-listener `Gateway`…)._
