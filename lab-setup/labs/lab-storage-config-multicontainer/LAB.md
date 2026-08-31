# 💾 Lab — Storage · ConfigMap/Secrets · Sidecars

> **Themed lab** (not a mock exam): it focuses on **workload configuration and
> persistence** — *storage* (PV/PVC/StorageClass), *config* (ConfigMap/Secrets)
> and *multi-container Pods* (shared emptyDir, native sidecar).
> The tasks are **nearly independent** and of increasing difficulty: you can play just one at a time.
> **100 pts**, target **≥ 75 %**. No time limit — this is a practice lab.

> ⚠️ **No dynamic provisioner (CSI) is installed** (bare kubeadm cluster). The *StorageClass* in A1
> is therefore graded on the **object** (its fields), like an Ingress with no controller. However, the
> **static PV↔PVC binding** (hostPath) and the **Pods** are tested **live**: the grader reads the
> real status (`Bound`, `Running`) and **execs** into the Pods to verify mounts, env variables and
> shared files.

## Getting started
```bash
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/setup.sh"   # seed the starting state
# … you solve the tasks …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"   # grade yourself (read-only)
```
> `setup.sh` is **idempotent**: it recreates the `storage-lab`, `config-lab`, `multi-lab` namespaces,
> (re)creates the *PersistentVolumes* `pv-data` and `pv-archive`, and deliberately leaves `pv-archive`
> in the **`Released`** state (for task A4). It cleans up your previous answers before re-seeding.
> The solutions are in [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — open it only afterwards.

---

## 💾 Domain A — Persistent storage (40 pts) · Namespace `storage-lab`

### A1 — Create a StorageClass (8 pts)
Create a *StorageClass* named **`fast-local`** with:

- provisioner **`example.com/fast-provisioner`** (illustrative — no controller behind it);
- **`volumeBindingMode: WaitForFirstConsumer`**;
- **`reclaimPolicy: Retain`**;
- **`allowVolumeExpansion: true`**.

> 💡 A *StorageClass* has **no** `spec` block: `provisioner`, `reclaimPolicy`, `volumeBindingMode`
> and `allowVolumeExpansion` are **top-level** fields. `WaitForFirstConsumer` delays volume
> creation until a Pod consumes the PVC (useful for multi-zone topology).
> Expected: `fast-local` — provisioner `example.com/fast-provisioner`, `WaitForFirstConsumer`, `Retain`, expansion **enabled**.

### A2 — Bind a PVC to a static PV (10 pts)
A *PersistentVolume* **`pv-data`** (hostPath, **5Gi**, `ReadWriteOnce`, `storageClassName: manual`)
already exists. In `storage-lab`, create a *PVC* **`app-data`** that binds to it:
**2Gi**, `ReadWriteOnce`, `storageClassName: manual`.

> 💡 **Static** binding depends on no provisioner: the controller matches the PVC to a
> **compatible** PV (same `storageClassName`, `accessModes` included, capacity ≥ request). Verify:
> `kubectl -n storage-lab get pvc app-data` (`STATUS` column = `Bound`, `VOLUME` = `pv-data`).
> Expected: `app-data` is **`Bound`** and bound precisely to **`pv-data`**.

### A3 — Consume the PVC in a Pod (10 pts)
Create a *Pod* **`app`** (image `busybox:1.36`, kept alive — e.g. `sleep 100000`) that **mounts**
the `app-data` PVC on **`/data`**. Then create an empty file **`/data/ready`** in that volume.

> 💡 Two pieces: `spec.volumes[].persistentVolumeClaim.claimName: app-data` and, in the container,
> `volumeMounts[].mountPath: /data`. The file is created after startup: `kubectl -n storage-lab exec app -- touch /data/ready`.
> Expected: `app` `Running`, volume backed by the `app-data` PVC mounted on `/data`, and the file `/data/ready` present.

### A4 — Recover a PV stuck in `Released` (12 pts)
The *PersistentVolume* **`pv-archive`** (3Gi, `storageClassName: archive`, `reclaimPolicy: Retain`)
is stuck in **`Released`**: its former PVC was deleted but the stale **`claimRef`** blocks
any new binding. Make it reusable again, then bind a new PVC to it:

1. **Unblock** `pv-archive` so it returns to `Available`.
2. Create a *PVC* **`archive`** in `storage-lab` (`ReadWriteOnce`, **2Gi**, `storageClassName: archive`)
   that **binds** to `pv-archive`.

> 💡 `kubectl get pv pv-archive -o yaml` shows a `spec.claimRef` block (namespace + name + stale **uid**).
> As long as it is present with a `uid` that matches no PVC, the PV stays `Released`. Remove that
> block (`kubectl edit pv pv-archive` → delete `claimRef`, or `kubectl patch pv pv-archive --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'`).
> Expected: `pv-archive` is **no longer `Released`** (Available then Bound) and the `archive` PVC is **`Bound`** to `pv-archive`.

---

## ⚙️ Domain B — ConfigMap & Secrets (35 pts) · Namespace `config-lab`

### B1 — Multi-key ConfigMap (8 pts)
Create a *ConfigMap* named **`app-config`** with **three** keys:

- **`APP_MODE=production`**
- **`LOG_LEVEL=info`**
- **`MAX_CONNECTIONS=100`**

> 💡 `kubectl -n config-lab create configmap app-config --from-literal=APP_MODE=production --from-literal=LOG_LEVEL=info --from-literal=MAX_CONNECTIONS=100`.
> Expected: `app-config` contains the 3 exact keys/values.

### B2 — Opaque Secret (7 pts)
Create a *Secret* **`db-credentials`** (type **`Opaque`**) with:

- **`username=admin`**
- **`password=S3cr3t-pass`**

> 💡 `kubectl -n config-lab create secret generic db-credentials --from-literal=username=admin --from-literal=password=S3cr3t-pass`
> (the values are stored as **base64** — this is not encryption).
> Expected: `db-credentials` of type `Opaque`, with `username` and `password` decoding to the right values.

### B3 — Inject the config as environment variables (10 pts)
Create a *Pod* **`api`** (image `busybox:1.36`, kept alive) that receives:

- **all** the keys of `app-config` as env variables (**`envFrom`**);
- a **`DB_PASSWORD`** variable whose value comes from the **`password`** key of the `db-credentials` Secret (**`secretKeyRef`**).

> 💡 `envFrom: [{ configMapRef: { name: app-config } }]` imports each key as a variable of the same name.
> `DB_PASSWORD` is done with `env: [{ name: DB_PASSWORD, valueFrom: { secretKeyRef: { name: db-credentials, key: password } } }]`.
> Verify: `kubectl -n config-lab exec api -- printenv APP_MODE DB_PASSWORD`.
> Expected: in `api`, `APP_MODE=production`, `MAX_CONNECTIONS=100` (via `envFrom`) and `DB_PASSWORD=S3cr3t-pass` (via `secretKeyRef`).

### B4 — Mount a ConfigMap as a volume (10 pts)
1. Create a *ConfigMap* **`web-index`** with a key **`index.html`** whose content contains the string **`CKA Storage Lab`**.
2. Create a *Pod* **`web`** (image `nginx:1.29-alpine`) that **mounts** `web-index` as a **volume** on **`/usr/share/nginx/html`** (the `index.html` key thus becomes the served file).

> 💡 A ConfigMap mounted as a volume exposes **each key as a file** (`mountPath/<key>`). Here the
> `index.html` key replaces nginx's default page. `spec.volumes[].configMap.name: web-index` +
> `volumeMounts[].mountPath: /usr/share/nginx/html`. Verify: `kubectl -n config-lab exec web -- cat /usr/share/nginx/html/index.html`.
> Expected: `web` `Running`, and `/usr/share/nginx/html/index.html` indeed contains `CKA Storage Lab`.

---

## 🧩 Domain C — Sidecars & multi-container Pods (25 pts) · Namespace `multi-lab`

### C1 — Two containers sharing an `emptyDir` (13 pts)
Create a *Pod* **`shared-logs`** with **two** containers sharing an **`emptyDir`** volume mounted on
**`/var/log/app`** in both:

- **`writer`** (`busybox:1.36`) writes continuously to **`/var/log/app/app.log`** (e.g. the date every second);
- **`sidecar`** (`busybox:1.36`) **reads** that same file (e.g. `tail -f /var/log/app/app.log`).

> 💡 An `emptyDir` is **shared** between the containers of the same Pod (lifetime = the Pod's).
> Mount the **same** volume in both containers. Typical writer: `sh -c 'while true; do date >> /var/log/app/app.log; sleep 1; done'`.
> Expected: `shared-logs` `Running` (2 containers), `emptyDir` mounted on `/var/log/app` **on both sides**, and `/var/log/app/app.log` **non-empty** (the sidecar sees what the writer writes).

### C2 — "Native" sidecar (initContainer `restartPolicy: Always`) (12 pts)
Create a *Pod* **`web-agent`** with:

- a main container **`web`** (`nginx:1.29-alpine`);
- a **native sidecar** named **`log-agent`** (`busybox:1.36`, long-running — e.g. `sleep 100000`),
  declared as an **`initContainer`** carrying **`restartPolicy: Always`**.

> 💡 Since K8s **1.29**, an `initContainer` with `restartPolicy: Always` is a **native sidecar**: it
> starts **before** the main containers **and** stays alive the whole time (unlike a classic
> initContainer, which must terminate). It's the recommended modern pattern (log shipper, proxy…).
> Expected: `web-agent` `Running`, with an `initContainer` `log-agent` whose `restartPolicy=Always` is **always active**, and the `web` container started.

---

_This lab is extensible: say "add a task on `<topic>`" (e.g. `projected volume`, `subPath`,
`immutable` ConfigMap/Secret, `defaultMode`/`items`, `docker-registry` secret, PVC resize…)._
