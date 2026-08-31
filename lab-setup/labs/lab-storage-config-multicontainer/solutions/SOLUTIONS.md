# ✅ Lab — Storage · ConfigMap/Secrets · Sidecars · SOLUTIONS

> **Open this file only after your attempt.** Each solution matches exactly the criteria of `grade.sh`.
> All commands are to be run from `cp1` (`vagrant ssh cp1`).

---

## 💾 Domain A — Persistent storage

### A1 — StorageClass `fast-local`
```bash
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
provisioner: example.com/fast-provisioner
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

kubectl get sc fast-local -o wide
```
> Key points: a *StorageClass* has **no** `spec` — `provisioner`, `reclaimPolicy`,
> `volumeBindingMode` and `allowVolumeExpansion` are **top-level**. `WaitForFirstConsumer`
> delays provisioning until the Pod is scheduled (essential in multi-AZ). The provisioner here
> is illustrative: no volume will actually be created (we grade the object).

### A2 — Bind a PVC to a static PV
```bash
kubectl -n storage-lab apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 2Gi
EOF

kubectl -n storage-lab get pvc app-data          # STATUS=Bound, VOLUME=pv-data
```
> Key points: **static** binding = no provisioner. The controller picks a compatible PV:
> same `storageClassName` (`manual`), `accessModes` included (RWO), capacity **≥** request (2Gi ≤ 5Gi).
> You can therefore get a PV **larger** than requested.

### A3 — Consume the PVC in a Pod
```bash
kubectl -n storage-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "100000"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-data
EOF

kubectl -n storage-lab wait --for=condition=Ready pod/app --timeout=60s
kubectl -n storage-lab exec app -- touch /data/ready        # create the expected file
kubectl -n storage-lab exec app -- ls -l /data
```
> Key points: the Pod references the PVC by `claimName` (it does not **own** the PVC → the PVC outlives the Pod).
> The file written in `/data` lives on the `hostPath` of the node where the Pod lands (it doesn't matter here: we read it back via `exec`).

### A4 — Recover a PV stuck in `Released`
```bash
# 1) Diagnosis: the stale claimRef blocks rebinding
kubectl get pv pv-archive                                   # STATUS=Released
kubectl get pv pv-archive -o jsonpath='{.spec.claimRef}{"\n"}'

# 2) Remove the claimRef → the PV returns to Available
kubectl patch pv pv-archive --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
#   (interactive equivalent: kubectl edit pv pv-archive  → delete the whole spec.claimRef block)
kubectl get pv pv-archive                                   # STATUS=Available

# 3) New PVC that binds to the released PV
kubectl -n storage-lab apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: archive
  resources:
    requests:
      storage: 2Gi
EOF

kubectl -n storage-lab get pvc archive                      # STATUS=Bound, VOLUME=pv-archive
```
> Key points: with `reclaimPolicy: Retain`, deleting the PVC leaves the PV in **`Released`** with a
> `spec.claimRef` (namespace + name + stale **uid**) that prevents it from rebinding — even to a PVC of
> the same name (the `uid` no longer matches). Remove `claimRef` → `Available`, then a compatible PVC binds to it.
> ⚠️ The **data** stays on the volume; to start clean, you would wipe the backend first.

---

## ⚙️ Domain B — ConfigMap & Secrets

### B1 — Multi-key ConfigMap
```bash
kubectl -n config-lab create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=info \
  --from-literal=MAX_CONNECTIONS=100

kubectl -n config-lab get cm app-config -o yaml
```
> Key points: `--from-literal` per key. (Other useful sources: `--from-file=cfg.properties`,
> `--from-env-file=vars.env`.) All these keys are valid identifiers → reusable as-is in `envFrom` (B3).

### B2 — Opaque Secret
```bash
kubectl -n config-lab create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=S3cr3t-pass

kubectl -n config-lab get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
```
> Key points: `secret generic` = type **`Opaque`**. The values are **base64** (encoding, **not**
> encryption) → anyone able to read the Secret sees the value. `create secret generic` encodes
> automatically; in raw YAML you would put the base64 under `data:` (or the plaintext under `stringData:`).

### B3 — Inject the config as environment variables
```bash
kubectl -n config-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: ["sleep", "100000"]
    envFrom:
    - configMapRef:
        name: app-config
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
EOF

kubectl -n config-lab exec api -- printenv APP_MODE MAX_CONNECTIONS DB_PASSWORD
```
> Key points: `envFrom` imports **all** the ConfigMap keys as variables of the same name
> (`APP_MODE`, `LOG_LEVEL`, `MAX_CONNECTIONS`). `secretKeyRef` targets **one** specific key of the Secret and
> renames it (`DB_PASSWORD`). ⚠️ Injected as an **env variable**, a ConfigMap/Secret value is **frozen**
> at Pod creation → a later change requires `kubectl rollout restart` (or recreating the Pod).

### B4 — Mount a ConfigMap as a volume
```bash
# 1) ConfigMap with file content (index.html key)
kubectl -n config-lab create configmap web-index \
  --from-literal=index.html='<h1>CKA Storage Lab</h1>'

# 2) nginx Pod that mounts the ConfigMap on the docroot
kubectl -n config-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    volumeMounts:
    - name: content
      mountPath: /usr/share/nginx/html
  volumes:
  - name: content
    configMap:
      name: web-index
EOF

kubectl -n config-lab exec web -- cat /usr/share/nginx/html/index.html
```
> Key points: a ConfigMap mounted as a **volume** exposes **each key → a file** (`mountPath/<key>`,
> content = value). The `index.html` key thus becomes `/usr/share/nginx/html/index.html`. Useful options:
> `items:` (mount only certain keys, optionally renamed via `path`), `defaultMode` (permissions),
> `subPath` (mount **one** file without masking the directory — but breaks hot reload).
> Unlike `envFrom`, a ConfigMap volume is **refreshed** automatically (kubelet delay, except `subPath`).

---

## 🧩 Domain C — Sidecars & multi-container Pods

### C1 — Two containers sharing an `emptyDir`
```bash
kubectl -n multi-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: shared-logs
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 1; done"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: sidecar
    image: busybox:1.36
    command: ["sh", "-c", "tail -f /var/log/app/app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  volumes:
  - name: logs
    emptyDir: {}
EOF

kubectl -n multi-lab exec shared-logs -c sidecar -- head /var/log/app/app.log
```
> Key points: an `emptyDir` is an **ephemeral volume shared** by all containers of the Pod (created at
> Pod startup, erased on its deletion). The **same** volume mounted in both containers = a writer→reader
> exchange channel (the classic log shipper pattern). `emptyDir.medium: Memory` = tmpfs (counted in `limits.memory`).

### C2 — "Native" sidecar (initContainer `restartPolicy: Always`)
```bash
kubectl -n multi-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-agent
spec:
  initContainers:
  - name: log-agent            # ← sidecar NATIF : initContainer + restartPolicy Always
    image: busybox:1.36
    restartPolicy: Always
    command: ["sleep", "100000"]
  containers:
  - name: web
    image: nginx:1.29-alpine
EOF

kubectl -n multi-lab get pod web-agent -o jsonpath='{.status.initContainerStatuses[0].state}{"\n"}'
```
> Key points: since K8s **1.29**, an `initContainer` with **`restartPolicy: Always`** is a **native
> sidecar**: it starts **before** the main containers (like an init) **but** stays alive the whole
> time (unlike a classic initContainer, which must terminate). Advantages vs the "2nd
> container" pattern: guaranteed startup order, doesn't block a Job from finishing, lifecycle managed by the kubelet.

---

> 💡 Reminder: no CSI provisioner is installed — the *StorageClass* (A1) is graded on the **object**,
> while the static binding (A2/A4) and the Pods (A3, B3, B4, C1, C2) are validated **live**.
> In production, a provisioner (local-path, EBS CSI, Ceph…) would materialize dynamic storage.
