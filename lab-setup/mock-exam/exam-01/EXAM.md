# 🧪 CKA — Mock exam (kubeadm lab)

> **Real CKA format**: 2 h · hands-on tasks · **pass mark 66%** · weighted scoring below.
> Environment: the lab cluster (`cp1` + `w1` + `w2`, K8s 1.34, Calico).
> **The solutions are NOT in this file** → see `solutions/SOLUTIONS.md` (open it only afterwards).

---

## ⚙️ Getting started (before starting the clock)

```bash
# From the host machine, in lab-setup/

# 0. (Re)deploy the lab if needed — cluster 1 CP + 2 workers (K8s 1.34, Calico)
vagrant up --no-parallel        # first time: brings up the VMs; otherwise starts the stopped ones
vagrant ssh cp1 -c "kubectl get nodes"   # validate: cp1/w1/w2 Ready before continuing

# 1. Seed the exam environment (namespaces + broken resources)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"

# 2. Connect to the control plane to work
vagrant ssh cp1
```

All commands run from `cp1` (admin kubeconfig already in place).
Handy aliases already loaded: `k`, `$do` (`--dry-run=client -o yaml`), `$now`.

## 📏 Rules

- **A single cluster** here (no `use-context` to do), but **read carefully the namespace** required by each task.
- You may use the official docs `kubernetes.io/docs` (as in the exam).
- Grading is **automatic**: each task is checked by `grade.sh`. Match **names, namespaces, labels and ports** exactly.
- **Total: 100 points** distributed by the real curriculum weights. Target: **≥ 66**.

| Domain | Weight | Tasks |
|---|---|---|
| Cluster Architecture | 25 | T1–T4 |
| Workloads & Scheduling | 15 | T5–T7 |
| Services & Networking | 20 | T8–T10 |
| Storage | 10 | T11–T12 |
| Troubleshooting | 30 | T13–T16 |

> 🏷️ **GOLDEN RULE — the namespace is worth points.** Each task requires a specific namespace (badge `🏷️ ns` in its title). A correct resource **created in the wrong namespace = 0 points** (the real CKA checks the namespace exactly). Habit: put **`-n <namespace>`** on *every* command, and check with `kubectl -n <namespace> get …` before moving on. Tasks **T2, T3, T4** act at **node/cluster** level (no namespace).

---

## 🏛️ Cluster Architecture (25 pts)

### T1 — RBAC (7 pts) · 🏷️ **ns `rbac-test`**
In namespace `rbac-test`:
1. Create a **ServiceAccount** `deploy-bot`.
2. Create a **Role** `pod-reader` allowing only `get`, `list`, `watch` on **pods**.
3. Bind the two with a **RoleBinding** `deploy-bot-read`.

> Expected: `deploy-bot` can **list** the pods in `rbac-test` but **cannot** delete them.

### T2 — etcd backup (8 pts) · on `cp1`
Take an **etcd snapshot** of the cluster and save it to the file **`/opt/etcd-backup.db`** on `cp1`.
Use the control plane certificates (`/etc/kubernetes/pki/etcd/…`).

> Expected: `/opt/etcd-backup.db` exists and is a **valid** etcd snapshot.

### T3 — Static Pod (5 pts) · on `w1`
On node **`w1`**, create a **static pod** named `static-web` (image `nginx:1.29-alpine`) via the kubelet's static-manifests directory.

> Expected: a pod **`static-web-w1`** appears `Running` in namespace `default`.

### T4 — Node maintenance (5 pts)
Node **`w2`** must go into maintenance. Mark it so that **no new pod** schedules onto it (without deleting it or its existing pods).

> Expected: `w2` in state `SchedulingDisabled`.

---

## 📦 Workloads & Scheduling (15 pts)

### T5 — Deployment + scale (5 pts) · 🏷️ **ns `workloads`**
Create a Deployment **`web`**: image **`nginx:1.29-alpine`**, **3 replicas**, `containerPort` 80.

> Expected: 3 pods `Ready`, correct image.

### T6 — ConfigMap → env variable (5 pts) · 🏷️ **ns `workloads`**
1. Create a **ConfigMap** `app-config` with the key **`APP_COLOR=blue`**.
2. Create a **Pod** `color-pod` (image `busybox:1.36`, command `sleep 100000`) that exposes the environment variable **`APP_COLOR`** from this ConfigMap.

> Expected: `color-pod` `Running`, variable `APP_COLOR` injected from the ConfigMap.

### T7 — Label-based placement (5 pts) · 🏷️ **ns `workloads`**
1. Add the label **`disktype=ssd`** to node **`w1`**.
2. Create a Pod **`ssd-pod`** (image `nginx:1.29-alpine`) that, via a **`nodeSelector`**, can schedule **only** onto a node `disktype=ssd`.

> Expected: `ssd-pod` `Running` **on `w1`**.

---

## 🌐 Services & Networking (20 pts)

### T8 — Service ClusterIP (5 pts) · 🏷️ **ns `workloads`**
Expose the Deployment `web` (T5) via a **ClusterIP** Service named **`web-svc`**, port **80** → targetPort **80**.

> Expected: `web-svc` of type ClusterIP with **3 endpoints**.

### T9 — Service NodePort (5 pts) · 🏷️ **ns `workloads`**
Create a **NodePort** Service named **`web-np`** for the Deployment `web`, port **80**, **nodePort `30080`**.

> Expected: `web-np` type NodePort, nodePort `30080`, endpoints present.

### T10 — NetworkPolicy (10 pts) · 🏷️ **ns `netpol`**
Namespace `netpol` already contains `backend` (label `app=backend`, listens on `:80`, Service `backend`), `frontend` (`app=frontend`) and `client` (`app=other`).
Create a **NetworkPolicy** **`backend-allow-frontend`** that: on pods `app=backend`, allows **ingress** traffic **only** from pods `app=frontend`, on **port 80**.

> Expected: `frontend` can reach `backend:80`, **`client` can no longer**.

---

## 💾 Storage (10 pts)

### T11 — PV + PVC (6 pts) · 🏷️ **ns `storage`**
1. Create a **PersistentVolume** `pv-manual`: `1Gi`, `hostPath` `/mnt/data`, `accessModes: ReadWriteOnce`, `storageClassName: manual`.
2. Create a **PVC** `pvc-manual` in `storage`: `500Mi`, `ReadWriteOnce`, `storageClassName: manual`.

> Expected: `pvc-manual` is **`Bound`** to `pv-manual`.

### T12 — Pod mounting the PVC (4 pts) · 🏷️ **ns `storage`**
Create a Pod **`pv-pod`** (image `nginx:1.29-alpine`) that mounts the PVC `pvc-manual` at **`/usr/share/nginx/html`**.

> Expected: `pv-pod` `Running` with the `pvc-manual` volume mounted at the correct path.

---

## 🔧 Troubleshooting (30 pts)

> These resources are **already deployed and broken** by `setup.sh`. **Repair them.**

### T13 — Pods that won't start (6 pts) · 🏷️ **ns `trouble`**
The Deployment **`tshoot-web`** is in `ImagePullBackOff`. Fix it so it runs (valid image **`nginx:1.29-alpine`**).

> Expected: `tshoot-web` available, pods `Running`.

### T14 — Service with no endpoints (8 pts) · 🏷️ **ns `trouble`**
The Service **`api-svc`** returns no endpoints even though the Deployment `api` is running. Find and fix the cause.

> Expected: `api-svc` has **endpoints** (the `api` pods).

### T15 — Pod `Pending` (8 pts) · 🏷️ **ns `trouble`**
The Pod **`hungry`** stays `Pending` and never schedules. Make it run (the pod must still be named `hungry`, image `nginx:1.29-alpine`).

> Expected: a pod `hungry` `Running` in `trouble`.

### T16 — Deployment stuck on creation (8 pts) · 🏷️ **ns `trouble`**
The Deployment **`cfg-app`** is stuck: it mounts a ConfigMap **`cfg-app-config`** that does not exist. Create this ConfigMap with a key **`app.properties`** containing `mode=prod`, to unblock the pods.

> Expected: ConfigMap `cfg-app-config` (key `app.properties`) present **and** pods `cfg-app` `Running`.

---

## ✅ Grading

```bash
bash /vagrant/mock-exam/exam-01/grade.sh
```

The script prints the per-task detail, the per-domain score, and the **total /100** with a verdict (**≥ 66 = pass**).
