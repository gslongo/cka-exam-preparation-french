# 🧪 CKA — Mock exam #2 · advanced level (kubeadm lab)

> **Real CKA format**: 2 h · hands-on tasks · **pass mark 66%** · weighted scoring below.
> Environment: the lab cluster (`cp1` + `w1` + `w2`, K8s 1.34, Calico).
> **Harder than exam-01**: cluster-scoped RBAC, **kubeadm upgrade**, manual scheduling, taints/tolerations, Secrets, **Ingress**, default-deny NetworkPolicy, `reclaimPolicy`/`subPath`, and less obvious troubleshooting (probe, **DNS resolution**, placement constraint, missing Secret).
> **The solutions are NOT in this file** → see `solutions/SOLUTIONS.md` (open it only afterwards).

---

## ⚙️ Getting started (before starting the clock)

```bash
# From the host machine, in lab-setup/

# 0. ⚠️ IMPORTANT — this exam contains an IRREVERSIBLE UPGRADE task (T2,
#    to be done LAST) which upgrades the cluster from 1.34 to 1.35.
#    setup.sh CANNOT downgrade the cluster: start from a FRESHLY deployed
#    1.34 cluster before you begin this exam.
vagrant destroy -f && vagrant up --no-parallel   # start clean (cluster 1.34)
vagrant ssh cp1 -c "kubectl get nodes"           # verify: cp1/w1/w2 Ready (v1.34.x)

# 1. Seed exam #2 (namespaces + broken resources)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/setup.sh"

# 2. Connect to the control plane to work
vagrant ssh cp1
```

All commands run from `cp1` (admin kubeconfig already in place), **except T3** (static pod, on `w1`).
Handy aliases already loaded: `k`, `$do` (`--dry-run=client -o yaml`), `$now`.

## 📏 Rules

- **A single cluster** here (no `use-context` to run), but **read carefully the namespace** required by each task.
- You may use the official docs `kubernetes.io/docs` (as in the exam).
- Grading is **automatic**: each task is checked by `grade.sh`. Match **names, namespaces, labels, ports** exactly.
- **Total: 100 points** split by the real curriculum weights. Target: **≥ 66**.

| Domain | Weight | Tasks |
|---|---|---|
| Cluster Architecture | 25 | T1–T4 |
| Workloads & Scheduling | 15 | T5–T7 |
| Services & Networking | 20 | T8–T10 |
| Storage | 10 | T11–T12 |
| Troubleshooting | 30 | T13–T16 |

> 🏷️ **GOLDEN RULE — the namespace is worth points.** Each task requires a specific namespace (badge `🏷️ ns` in its title). A correct resource but **created in the wrong namespace = 0 points** (the real CKA checks the namespace exactly). Reflex: put **`-n <namespace>`** on *every* command, and verify with `kubectl -n <namespace> get …` before moving on. Tasks **T2, T3** act at the **node/cluster** level (no namespace).

---

## 🏛️ Cluster Architecture (25 pts)

### T1 — Cluster-scoped RBAC (7 pts) · 🏷️ **ns `platform`**
1. Create a **ServiceAccount** `ci-bot` in the `platform` namespace.
2. Create a **ClusterRole** `deploy-admin` allowing `get`, `list`, `watch`, `create`, `update`, `patch` on **deployments** (`apps`).
3. Bind them with a **ClusterRoleBinding** `ci-bot-deploy` (cluster scope).

> Expected: `ci-bot` can **create a Deployment in any namespace** but **cannot** delete a node.

### T2 — Control plane upgrade 1.34 → 1.35 (8 pts) · on `cp1` · ⚠️ **DO THIS LAST (IRREVERSIBLE)**
Upgrade the **control plane node `cp1`** from Kubernetes **1.34** to **1.35** with `kubeadm`: switch the apt repo to `v1.35`, `kubeadm upgrade plan` then `kubeadm upgrade apply`, and update **`kubelet` + `kubectl`** (drain/uncordon `cp1`, restart the kubelet).

> ⚠️ **`cp1` ONLY — do NOT upgrade the workers.** Only `cp1` is graded. Draining `w1`/`w2` **permanently** evicts the "naked" pods from the other tasks (T4 `pinned`, T6 `secret-pod`, T7 `tolerant`, T12 `app`, T14 `dns-check`, T15 `stuck`, plus the `secure` seeds): with no controller, they are **not recreated** and you lose those points.
> ⚠️ **Irreversible operation**: do it **very last**, once all the other tasks are done. To retake the exam, you will have to redeploy the cluster (`vagrant destroy && vagrant up`).
> Expected: `kubectl get node cp1` shows a **`v1.35.x`** version.

### T3 — Static Pod with label (5 pts) · on `w1`
On node **`w1`**, create a **static pod** named `static-web` (image `nginx:1.29-alpine`, `containerPort` 80) via the kubelet's static-manifests directory. The pod must carry the **label `role=cache`**.

> Expected: a **`static-web-w1`** pod `Running` (namespace `default`) on `w1`, with the label `role=cache`.

### T4 — Manual scheduling (5 pts) · 🏷️ **ns `apps`**
Without going through the scheduler, place a Pod **`pinned`** (image `nginx:1.29-alpine`) **directly on node `w2`**.

> Expected: `pinned` `Running`, `spec.nodeName = w2`.

---

## 📦 Workloads & Scheduling (15 pts)

### T5 — Deployment + rollout strategy (5 pts) · 🏷️ **ns `apps`**
Create a Deployment **`api`**: image **`nginx:1.29-alpine`**, **3 replicas**, `containerPort` 80, `requests` `cpu=50m`/`memory=32Mi`, and a **RollingUpdate** strategy with **`maxUnavailable: 0`** (and `maxSurge: 1`).

> Expected: 3 `Ready` pods, correct image, `maxUnavailable = 0`.

### T6 — Secret → env variable (5 pts) · 🏷️ **ns `apps`**
1. Create a **Secret** `app-secret` with the key **`TOKEN=s3cr3t`**.
2. Create a **Pod** `secret-pod` (image `busybox:1.36`, command `sleep 100000`) that exposes the environment variable **`TOKEN`** from this Secret.

> Expected: `secret-pod` `Running`, `TOKEN` variable injected from the Secret `app-secret`.

### T7 — Taint + toleration (5 pts) · 🏷️ **ns `apps`**
1. Add to node **`w1`** the taint **`dedicated=cka:NoSchedule`**.
2. Create a Pod **`tolerant`** (image `nginx:1.29-alpine`) that **tolerates** this taint **and** schedules **on `w1`**.

> Expected: `w1` carries the taint `dedicated=cka:NoSchedule`; `tolerant` `Running` **on `w1`** with the matching toleration.

---

## 🌐 Services & Networking (20 pts)

### T8 — Ingress (5 pts) · 🏷️ **ns `apps`**
Create an **Ingress** named **`api-ing`** that routes host **`api.cka.local`**, path **`/`** (`pathType: Prefix`), to the Service **`api-np`** (defined in T9) on port **80**.

> Expected: Ingress `api-ing` with a host rule `api.cka.local` → service `api-np:80`, path `/` (Prefix).
> ℹ️ The lab has no Ingress controller installed: only the resource **definition** is graded (not real HTTP routing).

### T9 — Service NodePort (5 pts) · 🏷️ **ns `apps`**
Create a **NodePort** Service named **`api-np`** for the Deployment `api`, port **80**, **nodePort `30090`**. (This Service also serves as the **backend for the T8 Ingress**.)

> Expected: `api-np` of type NodePort, nodePort `30090`, endpoints present.

### T10 — NetworkPolicy default-deny + allow (10 pts) · 🏷️ **ns `secure`**
The `secure` namespace already contains `db` (label `app=db`, listens on `:80`, Service `db`), `web` (`app=web`) and `scanner` (`app=other`). Initially, everyone can reach `db`.
1. Create a **NetworkPolicy** **`default-deny-ingress`** that **blocks all ingress** in the namespace (empty podSelector, `policyTypes: [Ingress]`).
2. Create a **NetworkPolicy** **`allow-web-to-db`** that allows ingress to `app=db`, **only** from `app=web`, on **port 80**.

> Expected: `web` can reach `db:80`, **`scanner` can no longer**.

---

## 💾 Storage (10 pts)

### T11 — PV (Retain) + PVC (6 pts) · 🏷️ **ns `storage`**
1. Create a **PersistentVolume** `pv-fast`: `2Gi`, `hostPath` `/mnt/data-02` (**`type: DirectoryOrCreate`**, so the directory is created on the node), `accessModes: ReadWriteOnce`, `storageClassName: fast`, **`persistentVolumeReclaimPolicy: Retain`**.
2. Create a **PVC** `data` in `storage`: `1Gi`, `ReadWriteOnce`, `storageClassName: fast`.

> Expected: `data` is **`Bound`** to `pv-fast`, whose reclaim policy is **`Retain`**.

### T12 — Pod mounted via subPath (4 pts) · 🏷️ **ns `storage`**
Create a Pod **`app`** (image `nginx:1.29-alpine`) that mounts the PVC `data` at **`/usr/share/nginx/html`** using **`subPath: html`**.

> Expected: `app` `Running`, volume `data` mounted at the right path with `subPath: html`.

---

## 🔧 Troubleshooting (30 pts)

> These resources are **already deployed and broken** by `setup.sh`. **Fix them.**

### T13 — Deployment never `Ready` (6 pts) · 🏷️ **ns `trouble`**
The Deployment **`frontend`** is running but stays `0` available: its **readinessProbe** queries the wrong port. Fix it.

> Expected: `frontend` available (pods `Ready`).

### T14 — Broken DNS resolution (8 pts) · 🏷️ **ns `trouble`**
The Pod **`dns-check`** is running but **no longer resolves any name**: its DNS configuration points to an unreachable server. Fix it so it resolves the cluster service names (e.g. `kubernetes.default`).

> Expected: `dns-check` `Running` **and** able to resolve `kubernetes.default.svc.cluster.local` (via CoreDNS).

### T15 — Pod `Pending` (8 pts) · 🏷️ **ns `trouble`**
The Pod **`stuck`** stays `Pending`: it requires a placement constraint that no node satisfies. Make it run (the pod must still be named `stuck`, image `nginx:1.29-alpine`).

> Expected: a `stuck` pod `Running` in `trouble`.

### T16 — Deployment stuck on creation (8 pts) · 🏷️ **ns `trouble`**
The Deployment **`billing`** is stuck: it references an env variable from a **Secret `billing-secret`** that does not exist. Create this Secret with the key **`API_KEY`** (any value) to unblock the pods.

> Expected: Secret `billing-secret` (key `API_KEY`) present **and** `billing` pods `Running`.

---

## ✅ Grading

```bash
bash /vagrant/mock-exam/exam-02/grade.sh
```

The script prints the per-task detail (with the **observed symptom** on failure, never the solution), the score per domain, and the **total /100** with a verdict (**≥ 66 = passed**).
