# 🔧 Lab — Cross-cutting Troubleshooting · SOLUTIONS

> Diagnosis + fix for each breakage. The grader tests **the result** (repaired object,
> pod `Running`, traffic that flows), not the method: several paths are often valid.
> Common reflex: **`kubectl describe` → Events section**, then `logs` / `logs -p`.

---

## 🏛️ ARCH — Cluster Architecture & Nodes

### A1 — RBAC: `deploy-bot` has no permissions
**Diagnosis**
```bash
kubectl -n ts-arch auth can-i list pods --as=system:serviceaccount:ts-arch:deploy-bot   # no
kubectl -n ts-arch get rolebinding deploy-bot-read -o yaml   # subjects.name = deploy-bot-typo (≠ real SA)
```
**Fix** — correct the RoleBinding subject:
```bash
kubectl -n ts-arch patch rolebinding deploy-bot-read --type=json \
  -p='[{"op":"replace","path":"/subjects/0/name","value":"deploy-bot"}]'
# (or: kubectl -n ts-arch edit rolebinding deploy-bot-read  →  name: deploy-bot)
```
**Check**: `... can-i list pods ... = yes` and `... can-i delete pods ... = no`.
**Key points**: a `RoleBinding` binds a **subject** (SA/user/group) to a `Role`. A typo in
`subjects[].name` silently breaks the permissions (no error). `auth can-i --as=` is the diagnostic tool.

### A2 — Static pod broken on `cp1`
**Diagnosis**
```bash
kubectl get pod ts-static-cp1 -n default          # ImagePullBackOff
kubectl describe pod ts-static-cp1 | tail          # Failed to pull image "nginx:1.29-nope"
```
**Fix** — on node `cp1`, edit the static manifest:
```bash
vagrant ssh cp1            # from the host
sudo sed -i 's/nginx:1.29-nope/nginx:1.29-alpine/' /etc/kubernetes/manifests/ts-static.yaml
# the kubelet detects the change and recreates the pod on its own
```
**Key points**: a **static pod** is managed by the **kubelet** (`/etc/kubernetes/manifests/` directory),
not by the API. You don't fix it with `kubectl edit` (the mirror pod is read-only) but **on the node**.
It's not subject to the scheduler → `cp1`'s control-plane taint doesn't bother it. `ownerReferences.kind=Node` confirms a mirror pod.

### A3 — Node `w1` "out of service" (2 causes)
**Diagnosis**
```bash
kubectl -n ts-nodes get deploy billing            # 0/1 available
kubectl -n ts-nodes describe pod -l app=billing | tail   # FailedScheduling: unschedulable + untolerated taint
kubectl describe node w1 | grep -E 'Taints|Unschedulable'
```
**Fix** — clear **both** blockers:
```bash
kubectl uncordon w1                          # 1) SchedulingDisabled
kubectl taint node w1 maintenance-           # 2) taint NoSchedule
# variant for (2): keep the taint and add a toleration to the Deployment
#   kubectl -n ts-nodes patch deploy billing --type=json -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"maintenance","operator":"Exists","effect":"NoSchedule"}]}]'
```
**Key points**: two **cumulative** mechanisms prevent scheduling — `cordon`
(`.spec.unschedulable`) and a `NoSchedule` **taint**. `describe node` reveals both. Taint-effect recap:
`NoSchedule` (blocks scheduling), `PreferNoSchedule` (avoids if possible), `NoExecute` (**also evicts** pods without a toleration).

### A4 — ConfigMap stuck in `Terminating`
**Diagnosis**
```bash
kubectl -n ts-arch get cm stuck-cm            # old AGE, never deleted
kubectl -n ts-arch get cm stuck-cm -o jsonpath='{.metadata.finalizers}{"\n"}'   # ["example.com/hold"]
```
**Fix** — remove the finalizer:
```bash
kubectl -n ts-arch patch cm stuck-cm --type=merge -p '{"metadata":{"finalizers":null}}'
```
**Key points**: an object with a `deletionTimestamp` **+** a `finalizer` stays `Terminating` as long as the
finalizer isn't removed (the controller meant to do it is absent). Emptying `metadata.finalizers` unblocks the deletion.

---

## 📦 WORK — Workloads & Scheduling

### W1 — `web` in `ImagePullBackOff`
```bash
kubectl -n ts-work describe deploy web | tail          # tag "nginx:1.29-nope" not found
kubectl -n ts-work set image deploy/web web=nginx:1.29-alpine
```
**Key points**: on a **Deployment**, `set image` (or `edit`) triggers a rollout — no need to recreate.

### W2 — `crasher` in `CrashLoopBackOff`
```bash
kubectl -n ts-work logs crasher --previous       # -p: logs of the instance that crashed
# the command exits with an error (exit 1). command/args are IMMUTABLE on a pod → recreate:
kubectl -n ts-work delete pod crasher
kubectl -n ts-work run crasher --image=busybox:1.36 --command -- sh -c 'sleep 100000'
```
**Key points**: `logs --previous` is essential in CrashLoop (the current container just restarted).
A wrong `command:` overrides the `ENTRYPOINT` and makes the container exit immediately.

### W3 — `checkout` in `CreateContainerConfigError`
```bash
kubectl -n ts-work describe pod checkout | tail   # secret "app-secret": key "password" not found
kubectl -n ts-work patch secret app-secret --type=merge \
  -p "{\"data\":{\"password\":\"$(printf 'S3cret' | base64 -w0)\"}}"
# the kubelet retries on its own → checkout goes Running
```
**Key points**: a missing **key** in a `secretKeyRef`/`configMapKeyRef` blocks container creation.
Adding the key is enough (the pod doesn't need recreating, the kubelet retries).

### W4 — `report` in `Pending` (resources)
```bash
kubectl -n ts-work describe pod report | tail     # 0/3 nodes: Insufficient memory/cpu
kubectl -n ts-work delete pod report
kubectl -n ts-work run report --image=nginx:1.29-alpine
```
**Key points**: unreasonable `requests` → no node has enough `Allocatable`. The `resources`
are immutable on a pod → recreate with realistic requests (or none).

### W5 — `analytics` in `Pending` (nodeSelector)
```bash
kubectl -n ts-work describe pod analytics | tail  # didn't match node selector disktype=ssd
kubectl label node w2 disktype=ssd                # make a node eligible
# (or recreate the pod without the nodeSelector)
```
**Key points**: a `nodeSelector` with no matching node leaves the pod `Pending`. Two fixes:
**label** a node, or remove/correct the selector.

### W6 — `frontend` never `Ready`
```bash
kubectl -n ts-work get pods -l app=frontend       # Running but 0/1 READY
kubectl -n ts-work describe pod -l app=frontend | grep -A3 Readiness   # probe :8080 failing
kubectl -n ts-work patch deploy frontend --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]'
```
**Key points**: a failing **readinessProbe** leaves the pod `Running` but **NotReady** → it's removed
from its Service's endpoints. The symptom ("no traffic") is network, the **cause** is the probe.

### W7 — `cruncher` OOM-killed
```bash
kubectl -n ts-work get pod cruncher                    # CrashLoopBackOff, restarts climbing
kubectl -n ts-work describe pod cruncher | grep -B1 -A3 'Last State'
#   Reason: StartError — "container init was OOM-killed (memory limit too low?)"
# Pod resources are immutable → export, raise the limit, recreate:
kubectl -n ts-work get pod cruncher -o yaml > /tmp/cruncher.yaml
#   edit: resources.requests.memory and resources.limits.memory → 128Mi
kubectl replace --force -f /tmp/cruncher.yaml
kubectl -n ts-work get pod cruncher                    # Running 1/1, RESTARTS 0
```
**Key points**: the app writes ~50Mi into `/dev/shm`, and **tmpfs pages count against the
container's memory limit** — worse, they belong to the **pod sandbox**, so they survive container
restarts: after the first OOM kill, every restart dies instantly (`StartError… init was
OOM-killed`). Fix = a realistic limit, not removing limits. Pod `resources` are **immutable** →
recreate (`kubectl replace --force`), the same lesson as W4.

### W8 — `locked-web` crashes because of its securityContext
```bash
kubectl -n ts-work logs locked-web        # mkdir /var/cache/nginx/... permission denied
kubectl -n ts-work get pod locked-web -o jsonpath='{.spec.securityContext}{"\n"}'   # runAsUser: 4321
# securityContext is immutable → export, drop (or fix) it, recreate:
kubectl -n ts-work get pod locked-web -o yaml > /tmp/locked-web.yaml
#   edit: remove the pod-level securityContext block (nginx:1.29-alpine needs root to start)
kubectl replace --force -f /tmp/locked-web.yaml
kubectl -n ts-work get pod locked-web     # Running 1/1
```
**Key points**: the stock nginx image starts as **root** (then drops privileges for its workers);
forcing an arbitrary `runAsUser` breaks its startup (`/var/cache/nginx`, `/run/nginx.pid`).
Read the **container logs** — the crash reason is written there, not in the events. (A truly
non-root nginx needs the `nginxinc/nginx-unprivileged` image — not allowed here.)

---

## 🌐 NET — Services & Networking

### N1 — `api-svc` with no endpoints
```bash
kubectl -n ts-net get endpoints api-svc           # <none>
kubectl -n ts-net get pods --show-labels          # app=api  (the svc targets app=api-v1)
kubectl -n ts-net patch svc api-svc --type=merge -p '{"spec":{"selector":{"app":"api"}}}'
```
**Key points**: empty `endpoints` = **selector mismatch** (or NotReady pods). Compare the Service's
`selector` to the pods' real **labels**.

### N2 — `shop-svc`: wrong `targetPort`
```bash
kubectl -n ts-net get svc shop-svc -o wide        # port 80 → targetPort 8080
kubectl -n ts-net exec shop-client -- wget -T4 -qO- http://shop-svc   # fails
kubectl -n ts-net patch svc shop-svc --type=json \
  -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
```
**Key points**: endpoints present **but** traffic broken ⇒ often `targetPort` ≠ container's real port.
`port` = Service port, `targetPort` = target container port.

### N3 — NetworkPolicy `default-deny` blocks `client → backend`
```bash
kubectl -n ts-netpol get netpol                   # default-deny-ingress (podSelector: {})
kubectl -n ts-netpol exec client -- wget -T4 -qO- http://backend   # blocked
kubectl -n ts-netpol apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client-to-backend, namespace: ts-netpol }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - podSelector: { matchLabels: { app: client } }
    ports:
    - { protocol: TCP, port: 80 }
EOF
# (variant: delete the default-deny policy if no restriction is required)
```
**Key points**: NetworkPolicies are **additive** (OR). A `default-deny` (podSelector `{}`, Ingress)
blocks everything; you need a policy that explicitly **allows** the desired flow. Calico enforces it.

### N4 — `dns-broken` doesn't resolve services
```bash
kubectl -n ts-net exec dns-broken -- nslookup kubernetes.default   # fails
kubectl -n ts-net get pod dns-broken -o jsonpath='{.spec.dnsPolicy}{"\n"}'   # Default
# dnsPolicy is immutable on a pod → recreate with ClusterFirst:
kubectl -n ts-net delete pod dns-broken
kubectl -n ts-net run dns-broken --image=busybox:1.36 \
  --overrides='{"spec":{"dnsPolicy":"ClusterFirst"}}' --command -- sh -c 'sleep 100000'
```
**Key points**: `dnsPolicy: Default` inherits the `resolv.conf` **from the node** → **no** resolution of
`*.svc.cluster.local`. `ClusterFirst` (the real default) uses **CoreDNS**.

---

## 💾 STO — Storage

### S1 — PVC `data` in `Pending`
```bash
kubectl -n ts-storage get pvc data                # Pending
kubectl -n ts-storage describe pvc data | tail    # no volume plugin / no PV for storageClassName "fast"
kubectl get pv                                     # pv-small exists with storageClassName "slow"
# storageClassName is immutable on a PVC → recreate it aligned with the PV:
kubectl -n ts-storage delete pvc data
kubectl -n ts-storage apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: ts-storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: slow
  resources: { requests: { storage: 3Gi } }
EOF
```
**Key points**: without a dynamic provisioner, a PVC only binds to an **existing PV** whose
`storageClassName`, `accessMode` and capacity (≥ request) match.

### S2 — `app` stuck: missing PVC
```bash
kubectl -n ts-storage describe pod app | tail     # persistentvolumeclaim "app-pvc" not found
kubectl -n ts-storage apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: app-pvc, namespace: ts-storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local
  resources: { requests: { storage: 5Gi } }
EOF
# the PVC binds to pv-app → the pod starts (the kubelet retries the mount)
```
**Key points**: a `persistentVolumeClaim` volume pointing to a **nonexistent** PVC leaves the pod in
`ContainerCreating`. Creating the PVC (compatible with a free PV) unblocks the mount without recreating the pod.

---

## 🧭 General method (recap)

1. **Overview**: `kubectl get pods -A --field-selector=status.phase!=Running` + `get events -A --sort-by=.lastTimestamp`.
2. **A single object**: `describe` (Events!) → `logs` / `logs -p` → `get -o yaml`.
3. **Scheduling** (`Pending`): `describe pod` → `FailedScheduling` cause (resources, taint, nodeSelector, cordon).
4. **Network** ("no traffic"): `get endpoints` → selector/probes; `targetPort`; NetworkPolicy; DNS (`dnsPolicy`).
5. **Node**: `describe node` (Taints, Unschedulable, Conditions, Allocatable).
