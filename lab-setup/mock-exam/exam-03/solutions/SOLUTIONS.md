# ✅ CKA — Mock exam #3 (targeted drills) · SOLUTIONS

> **Open this file only after your attempt.** Each solution matches exactly the criteria of `grade.sh`.
> All commands are to be run from `cp1` (`vagrant ssh cp1`).

---

## 🏛️ Cluster Architecture & kubeconfig

### T1 — Extract information from a kubeconfig
We work only on the file provided via `--kubeconfig` (without touching `~/.kube/config`).

```bash
KC=/opt/exam-03/kubeconfig

# 1) All context names, one per line
kubectl config --kubeconfig=$KC get-contexts -o name > /opt/exam-03/contexts
#   (jsonpath equivalent: kubectl config --kubeconfig=$KC view \
#      -o jsonpath='{range .contexts[*]}{.name}{"\n"}{end}' )

# 2) Current context
kubectl config --kubeconfig=$KC current-context > /opt/exam-03/current-context

# 3) audit-user's client-certificate, decoded from base64
kubectl config --kubeconfig=$KC view --raw \
  -o jsonpath="{.users[?(@.name=='audit-user')].user.client-certificate-data}" \
  | base64 -d > /opt/exam-03/cert

# Check
cat /opt/exam-03/contexts
cat /opt/exam-03/current-context
head -1 /opt/exam-03/cert     # -----BEGIN CERTIFICATE-----
```

> Key points tested:
> - `kubectl config get-contexts -o name` (or jsonpath `.contexts[*].name`) to list.
> - `kubectl config current-context` for the active context.
> - `view --raw` is **essential**: without `--raw`, the certificate data is masked (`DATA+OMITTED`).
> - `base64 -d` to decode `client-certificate-data`.

---

## 📦 Packaging & Helm

### T2 — Install cert-manager with Helm + ClusterIssuer
```bash
# 1) Namespace
kubectl create namespace pki

# 2) Repo + chart install (release 'certman', CRDs included)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install certman jetstack/cert-manager \
  --namespace pki \
  --set crds.enabled=true

# Wait for cert-manager (especially the webhook) to be ready BEFORE creating the ClusterIssuer
kubectl -n pki rollout status deploy/certman-cert-manager-webhook
kubectl -n pki get pods

# 3) Edit the provided ClusterIssuer: add crlDistributionPoints under spec.selfSigned
#    /opt/exam-03/issuer.yaml becomes:
#    spec:
#      selfSigned:
#        crlDistributionPoints:
#        - http://pki.cka.local/crl

# 4) Create the ClusterIssuer
kubectl apply -f /opt/exam-03/issuer.yaml

# Check
helm list -n pki
kubectl get clusterissuer selfsigned-issuer -o jsonpath='{.spec.selfSigned.crlDistributionPoints[0]}{"\n"}'
```

> Key points tested:
> - `helm repo add` + `helm install <release> <chart> -n <ns> --set crds.enabled=true`.
> - The CRDs (`clusterissuers.cert-manager.io`, etc.) are laid down by the chart.
> - **Wait for the webhook**: without it, `kubectl apply` of the ClusterIssuer fails (`failed calling webhook`).
> - Edit a CR manifest then `kubectl apply -f`.

---

## 🧱 Workloads & Scheduling

### T3 — Scale a StatefulSet
```bash
# 1) Identify the controller that owns the store-db-* pods
kubectl -n project-store get statefulset

# 2) Scale to 1 replica (two equivalent ways)
kubectl -n project-store scale statefulset store-db --replicas=1
# or: kubectl -n project-store edit statefulset store-db   → spec.replicas: 1

# 3) Check
kubectl -n project-store get statefulset store-db
kubectl -n project-store get pods
```

> Key points tested:
> - Understand that Pods `xxx-0/1/2` belong to a **StatefulSet** (not a Deployment).
> - `kubectl scale statefulset` (or `edit`) rather than deleting the Pods (which would be recreated).
> - A StatefulSet deletes Pods in **reverse** order: `store-db-2` then `store-db-1`, keeping `store-db-0`.

### T4 — Pods evicted first (BestEffort QoS)
```bash
# See the QoS class of each Pod
kubectl -n project-qos get pods \
  -o custom-columns='NAME:.metadata.name,QOS:.status.qosClass'
# or: kubectl -n project-qos get pod <name> -o jsonpath='{.status.qosClass}'

# BestEffort are evicted first → write their names (one per line)
printf '%s\n' web-cache log-agent > /opt/exam-03/qos-evicted-first.txt
```

> QoS reminder:
> - **Guaranteed**: `requests == limits` for CPU **and** memory, on all containers.
> - **Burstable**: at least one `request` defined, but not Guaranteed.
> - **BestEffort**: no `request`/`limit` → **evicted first** under node-pressure.

### T5 — HPA via Kustomize
```bash
cd /opt/exam-03/kustomize/api-gw

# 1) HPA manifest in the base (autoscaling/v2)
cat > base/hpa.yaml <<'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gw
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gw
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

# 2) base/kustomization.yaml: remove configmap.yaml, add hpa.yaml
cat > base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
- hpa.yaml
EOF

# 3) overlays/prod: JSON6902 patch for maxReplicas=6
cat > overlays/prod/kustomization.yaml <<'EOF'
namespace: api-gw-prod
resources:
- ../../base
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: api-gw
  patch: |-
    - op: replace
      path: /spec/maxReplicas
      value: 6
EOF

# 4) apply does not prune → delete the ConfigMap already in the cluster
kubectl -n api-gw-staging delete configmap scaling-config
kubectl -n api-gw-prod    delete configmap scaling-config

# 5) Apply staging + prod
kubectl kustomize overlays/staging | kubectl apply -f -
kubectl kustomize overlays/prod    | kubectl apply -f -

# Check
kubectl -n api-gw-staging get hpa api-gw
kubectl -n api-gw-prod    get hpa api-gw
```

> Key points tested:
> - `kubectl apply` does not delete a resource removed from the kustomize → delete the ConfigMap explicitly (or `kubectl apply --prune`).
> - **prod** overlay: a **JSON6902 patch** changes `maxReplicas` without redefining the whole HPA (DRY).
> - HPA in `autoscaling/v2` with `metrics[].resource.target.averageUtilization: 50`.

### T6 — PV + PVC (without SC) mounted by a Deployment
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /mnt/data-vol
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage-app
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webstore
  namespace: storage-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstore
  template:
    metadata:
      labels:
        app: webstore
    spec:
      containers:
      - name: httpd
        image: httpd:2-alpine
        volumeMounts:
        - name: data
          mountPath: /var/www/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-pvc
EOF

# Check the binding
kubectl get pv data-pv
kubectl -n storage-app get pvc data-pvc
kubectl -n storage-app get deploy webstore
```

> Key points tested:
> - **Neither the PV nor the PVC** defines `storageClassName` → the PVC (empty SC) binds to the PV (empty SC). If there were a *default StorageClass*, you would need to set `storageClassName: ""` explicitly.
> - The volume is declared under `spec.template.spec.volumes` of a **Deployment** (not directly in a Pod), with the `volumeMount` on the container side.
> - `capacity` on the PV side vs `resources.requests.storage` on the PVC side.

### T7 — `kubectl top` scripts
```bash
cat > /opt/exam-03/node.sh <<'EOF'
kubectl top nodes
EOF

cat > /opt/exam-03/pod.sh <<'EOF'
kubectl top pods --containers
EOF
chmod +x /opt/exam-03/node.sh /opt/exam-03/pod.sh

# Test
bash /opt/exam-03/node.sh
bash /opt/exam-03/pod.sh
```

> Notes:
> - `--containers` details each container of a Pod (useful for multi-container Pods).
> - Add `-A` (`--all-namespaces`) to cover all namespaces.
> - metrics-server takes ~15-30 s to collect after startup (`kubectl top` returns an error before then).

### T8 — Join a worker + upgrade node
```bash
# 1) Join command generated from the control plane (real token + CA hash)
sudo kubeadm token create --print-join-command | tee /opt/exam-03/join-command.txt
#   → kubeadm join 192.168.56.10:6443 --token abcdef.0123456789abcdef \
#         --discovery-token-ca-cert-hash sha256:<hash>

# 2) Upgrade runbook for a WORKER (to run ON the worker, not on cp1)
cat > /opt/exam-03/upgrade-node.sh <<'EOF'
#!/usr/bin/env bash
# On the worker — match the exact control-plane version (e.g. v1.35.x)

# a) switch the apt repo to the right minor, then install the target kubeadm
sudo sed -i 's#v1\.[0-9]*/deb#v1.35/deb#' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm='1.35.0-1.1'   # adapter au patch du control plane
sudo apt-mark hold kubeadm

# b) upgrade the node's kubelet config (worker → 'upgrade node', NOT 'apply')
sudo kubeadm upgrade node

# c) drain from an admin machine:  kubectl drain <node> --ignore-daemonsets
# d) update kubelet + kubectl, then restart the service
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet='1.35.0-1.1' kubectl='1.35.0-1.1'
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# e) uncordon from an admin machine:  kubectl uncordon <node>
EOF
chmod +x /opt/exam-03/upgrade-node.sh
```

> Key points tested:
> - `kubeadm token create --print-join-command` produces **token + endpoint + CA hash** in a single command — it's the recommended way to add a worker (the initial bootstrap token expires after 24 h).
> - Key difference: the **control plane** uses `kubeadm upgrade apply <version>`, a **worker** uses `kubeadm upgrade node` (only updates the local kubelet config).
> - Worker order: apt repo → `kubeadm` → `kubeadm upgrade node` → drain → `kubelet`/`kubectl` → `restart kubelet` → uncordon. The version must match the control plane's **exactly** (version-skew rule: kubelet ≤ kube-apiserver).

### T9 — Query the Kubernetes API from a Pod (via ServiceAccount)
```bash
# 1) Pod using the ServiceAccount probe-sa
kubectl -n project-audit run secret-probe --image=nginx:1-alpine \
  --overrides='{"spec":{"serviceAccountName":"probe-sa"}}'
kubectl -n project-audit wait --for=condition=Ready pod/secret-probe --timeout=60s

# 2) From the Pod: token + CA mounted in /var/run/secrets/kubernetes.io/serviceaccount
kubectl -n project-audit exec secret-probe -- sh -c '
  apk add --no-cache curl >/dev/null 2>&1
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  curl -s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/$NS/secrets
' > /opt/exam-03/secrets.json

cat /opt/exam-03/secrets.json    # SecretList JSON containing audit-key
```

> Key points tested:
> - The Pod must reference the SA via `spec.serviceAccountName` (otherwise the mounted token is that of the `default` SA, without permissions).
> - The JWT token and the CA are mounted under `/var/run/secrets/kubernetes.io/serviceaccount/`; the internal API responds at `https://kubernetes.default.svc`.
> - The response is a `SecretList` **because** the SA has a `Role`/`RoleBinding` `get,list secrets` on the namespace (without RBAC → HTTP 403 `Forbidden`).

### T10 — DaemonSet on all nodes (including the control-plane)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-harvester
  namespace: project-batch
  labels:
    id: log-harvester
    uuid: 7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64
spec:
  selector:
    matchLabels:
      id: log-harvester
  template:
    metadata:
      labels:
        id: log-harvester
        uuid: 7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane   # planifier aussi sur cp1
        operator: Exists
        effect: NoSchedule
      containers:
      - name: harvester
        image: httpd:2-alpine
        resources:
          requests:
            cpu: 15m
            memory: 20Mi
EOF

kubectl -n project-batch get ds log-harvester -o wide   # DESIRED == number of nodes
```

> Key points tested:
> - A DaemonSet schedules **one Pod per** eligible **node**. Without a *toleration*, the control-plane (taint `NoSchedule`) is excluded → `DESIRED` = number of workers only.
> - The *toleration* `node-role.kubernetes.io/control-plane` (Exists/NoSchedule) allows including `cp1` → `DESIRED` = total number of nodes.
> - The `requests` (`cpu`/`memory`) and the labels are defined in the Pod **template**.

### T11 — Multi-container Deployment + anti-affinity
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-cache
  namespace: project-batch
  labels:
    id: edge-node
spec:
  replicas: 3
  selector:
    matchLabels:
      id: edge-node
  template:
    metadata:
      labels:
        id: edge-node
    spec:
      affinity:
        podAntiAffinity:                       # one Pod per node
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                id: edge-node
            topologyKey: kubernetes.io/hostname
      containers:
      - name: main
        image: nginx:1-alpine
      - name: sidecar
        image: registry.k8s.io/pause:3.10
EOF

kubectl -n project-batch get pods -l id=edge-node -o wide   # 2 Running + 1 Pending
```

> Key points tested:
> - `podAntiAffinity` **required** with `topologyKey: kubernetes.io/hostname` → the scheduler refuses two Pods with the same label on the same node.
> - 2 schedulable workers + 3 replicas → the 3rd Pod stays `Pending` (`0/x nodes available: didn't match pod anti-affinity`).
> - A `Deployment` can carry **multiple containers** in the same Pod (here `pause` serves as an auxiliary container).

### T13 — kubeadm certificate expiry & renewal
```bash
# 1) Expiration date of the kube-apiserver server certificate (openssl)
sudo openssl x509 -noout -enddate -in /etc/kubernetes/pki/apiserver.crt
#   notAfter=Aug  8 12:34:56 2026 GMT
sudo openssl x509 -noout -enddate -in /etc/kubernetes/pki/apiserver.crt \
  | cut -d= -f2 > /opt/exam-03/apiserver-expiration

# Confirm with kubeadm (same date expected)
sudo kubeadm certs check-expiration | grep apiserver

# 2) Targeted renewal command (do not run it)
echo 'sudo kubeadm certs renew apiserver' > /opt/exam-03/renew-apiserver.sh
```

> Key points tested:
> - `openssl x509 -enddate` and `kubeadm certs check-expiration` return the **same** `notAfter` date for `apiserver`.
> - The renewal can be **global** (`kubeadm certs renew all`) or **targeted** (`kubeadm certs renew apiserver`); here we target `apiserver`.
> - After a real renew, you must restart the control plane static Pods (kube-apiserver) to reload the certificate.

### T14 — NetworkPolicy egress (backend → cache-a/cache-b only)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: np-egress
  namespace: project-mesh
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Egress]
  egress:
  - to:                                  # rule 1: cache-a:6379
    - podSelector:
        matchLabels:
          app: cache-a
    ports:
    - protocol: TCP
      port: 6379
  - to:                                  # rule 2: cache-b:5432
    - podSelector:
        matchLabels:
          app: cache-b
    ports:
    - protocol: TCP
      port: 5432
EOF

# Check enforcement (by IP, without relying on DNS):
CA=$(kubectl -n project-mesh get pod -l app=cache-a -o jsonpath='{.items[0].status.podIP}')
VA=$(kubectl -n project-mesh get pod -l app=vault   -o jsonpath='{.items[0].status.podIP}')
kubectl -n project-mesh exec backend-1 -- /agnhost connect "$CA:6379" --timeout=3s   # OK (allowed)
kubectl -n project-mesh exec backend-1 -- /agnhost connect "$VA:9999" --timeout=3s   # TIMEOUT (blocked)
```

> Key points tested:
> - **egress** policy: as soon as a `backend` Pod is selected with `policyTypes: [Egress]`, **any** egress not listed is denied (so `vault:9999` is blocked).
> - **One `egress` rule per target** → `cache-a` is only reachable on `6379`, `cache-b` only on `5432`. Merging the `to`/`ports` into a single rule would allow the **cross-product** (cache-a:5432, cache-b:6379) — too permissive.
> - In practice, remember to also allow DNS egress (`UDP/TCP 53`) if the Pods resolve names.

### T16 — Inspect a container with `crictl`
```bash
# 1) Find the probe-httpd container ID on cp1
CID=$(sudo crictl ps --name probe-httpd -q | head -1)
echo "$CID"

# 2) ID + runtime type in container-info.txt
{
  echo "container-id: $CID"
  sudo crictl inspect "$CID" | grep -i runtimeType   # e.g. "runtimeType": "io.containerd.runc.v2"
} > /opt/exam-03/container-info.txt

# (jq variant)
# sudo crictl inspect "$CID" | jq '.info.runtimeType'

# 3) Container logs
sudo crictl logs "$CID" > /opt/exam-03/container.log 2>&1
```

> Key points tested:
> - `crictl` talks **directly to the runtime** (containerd) via the CRI socket: essential when the Kubernetes API no longer responds or to see containers that are not Pods (kubelet, pause…).
> - `crictl ps` ≠ `kubectl get pods`: you manipulate **containers** (sandbox/app IDs), not Pod objects. The `info.runtimeType` field confirms the low-level runtime (`io.containerd.runc.v2`).
> - `crictl logs <id>` reads the logs at the runtime level, whereas `kubectl logs` goes through the API server.

### T12 — HTTPRoute (Gateway API)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: route-splitter
  namespace: project-edge
spec:
  parentRefs:
  - name: edge-gw                 # attach to the existing Gateway
  rules:
  - matches:                       # /web -> web-svc
    - path:
        type: PathPrefix
        value: /web
    backendRefs:
    - name: web-svc
      port: 80
  - matches:                       # /svc -> api-svc
    - path:
        type: PathPrefix
        value: /svc
    backendRefs:
    - name: api-svc
      port: 80
  - matches:                       # /shop + X-Tier: premium (logical AND) -> premium-svc
    - path:
        type: PathPrefix
        value: /shop
      headers:
      - name: X-Tier
        value: premium
    backendRefs:
    - name: premium-svc
      port: 80
  - matches:                       # /shop catch-all (otherwise) -> standard-svc
    - path:
        type: PathPrefix
        value: /shop
    backendRefs:
    - name: standard-svc
      port: 80
EOF
```

> Key points tested:
> - **Gateway API** separates the roles: `GatewayClass`/`Gateway` (infra, provided) vs `HTTPRoute` (application routing, your responsibility) — where `Ingress` mixed everything together.
> - The route→gateway link is made via `parentRefs`, **not** via a class annotation.
> - A `match` that lists both `path` **and** `headers` applies a **logical AND**: both conditions must be true. Splitting them into two `matches` would give an **OR** (classic pitfall).
> - The **order of rules matters**: the `/shop` + header rule must precede the `/shop` catch-all, otherwise all `/shop` requests go to the default backend.
> - Conditional routing by header (`headers`) is not natively expressible with `Ingress`.
> - Without a Gateway controller installed, the object is **valid** but not programmed (no address) — the exam validates the **specification**.

### T15 — CoreDNS: custom domain `cka.local`
```bash
# 1) Back up BEFORE any change
kubectl -n kube-system get cm coredns -o yaml > /opt/exam-03/coredns_original.yaml

# 2) Edit the Corefile: add cka.local on the kubernetes plugin line
kubectl -n kube-system edit cm coredns
#   kubernetes cluster.local cka.local in-addr.arpa ip6.arpa {
#       ...
#   }

# 3) Reload CoreDNS
kubectl -n kube-system rollout restart deployment coredns
```

> Key points tested:
> - The `kubernetes` plugin accepts **multiple zones**: adding `cka.local` next to `cluster.local` makes the *Services* resolve under both domains.
> - **Always back up** the ConfigMap before editing: a Corefile mistake breaks DNS for the whole cluster.
> - The `reload` plugin automatically reloads the Corefile (≈ 30 s–2 min); `rollout restart` forces immediate application.

### T17 — etcd introspection
```bash
# etcd runs as a static pod: its flags are in the manifest
sudo grep -E 'key-file|cert-file|client-cert-auth' /etc/kubernetes/manifests/etcd.yaml

# Server certificate expiration
sudo openssl x509 -noout -enddate -in /etc/kubernetes/pki/etcd/server.crt

# Write the 3 pieces of information (free format)
cat > /opt/exam-03/etcd-info.txt <<'EOF'
server-private-key: /etc/kubernetes/pki/etcd/server.key
server-cert-expiration: Aug 10 12:52:19 2027 GMT
client-cert-auth: true (enabled)
EOF
```

> Key points tested:
> - The control plane components are **static Pods**: the truth of their configuration is in `/etc/kubernetes/manifests/*.yaml`, not in the API.
> - `--client-cert-auth=true` → etcd requires a valid **client certificate** (mTLS); this is what protects access to the database.
> - `openssl x509 -enddate` and `kubeadm certs check-expiration` must give the **same** date for the etcd server cert.

### T18 — A Service's iptables rules (kube-proxy)
```bash
# 1) Pod + Service ClusterIP 3100 -> 80
kubectl -n project-proxy run p-proxy --image=nginx:1-alpine
kubectl -n project-proxy expose pod p-proxy --name=proxy-svc --port=3100 --target-port=80

# 2) Assigned ClusterIP
CIP=$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.clusterIP}'); echo "$CIP"

# 3) iptables rules generated by kube-proxy (nat table)
sudo iptables-save -t nat | grep proxy-svc > /opt/exam-03/iptables.txt
#   (equivalent: sudo iptables-save -t nat | grep "$CIP")
cat /opt/exam-03/iptables.txt
```

Demonstration (optional): deleting the Service removes its rules.
```bash
kubectl -n project-proxy delete svc proxy-svc
sudo iptables-save -t nat | grep proxy-svc   # → no more lines
```

> Key points tested:
> - kube-proxy in **iptables** mode programs the `nat` table: `KUBE-SERVICES` → `KUBE-SVC-*` (one per Service) → `KUBE-SEP-*` (one per endpoint/Pod).
> - The **ClusterIP** is not a real interface: it's a **DNAT** rule that rewrites the destination to a Pod.
> - kube-proxy **reconciles continuously**: creating/deleting a Service immediately adds/removes its chains.

### T19 — Add a Services IP range (ServiceCIDR API)
```bash
# 0) Target Pod
kubectl -n project-range run range-probe --image=httpd:2-alpine

# 1) First Service — IP from the default range (ServiceCIDR "kubernetes")
kubectl -n project-range expose pod range-probe --name=range-svc --port=80

# 2) New Services IP range, live (without restarting kube-apiserver)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: extra-range
spec:
  cidrs:
  - 11.96.0.0/12
EOF

# 3) Second Service with a clusterIP from the new range
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: range-svc2
  namespace: project-range
spec:
  clusterIP: 11.96.0.10
  selector:
    run: range-probe
  ports:
  - port: 80
    targetPort: 80
EOF

kubectl get servicecidr
kubectl -n project-range get svc -o wide
kubectl get ipaddress | grep 11.96      # the allocated IP appears here
```

> Key points tested:
> - The **ServiceCIDR / IPAddress** API (GA) allows adding Services IP ranges **live**, without editing `--service-cluster-ip-range` or restarting `kube-apiserver`.
> - Each Service IP allocates an **IPAddress** object; `kubectl get ipaddress` lists the taken IPs and their parent Service.
> - The default range is the ServiceCIDR named `kubernetes`; its `spec.cidrs` field is **immutable** (the API rejects any modification: `field is immutable`). Even if a prompt says to "change" the range, the only possible operation is to **add** a complementary ServiceCIDR.
> - The old way (outside modern CKA), changing the range required modifying the kube-apiserver flag and **recreating** the Services — a disruptive operation that the ServiceCIDR API replaces.

---

## 🔁 Start over
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/setup.sh"   # re-initializes the starting state
```
