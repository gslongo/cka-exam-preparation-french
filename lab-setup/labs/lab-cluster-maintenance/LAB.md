# 🛠️ Lab — Cluster Maintenance, etcd & Security

> **CKA domain 01 — Cluster Architecture, Installation & Configuration (25%).**
> An **operational** lab: you run real cluster-admin tasks and grade the *result*.
> **100 pts · target ≥ 75 %.** All work is done **on cp1**. **Estimated time: ~45 min – 1 h 15** (8 tasks).

This lab complements the *Troubleshooting* lab (which repairs breakage): here you **operate**
the cluster like an administrator — back up etcd, sign a certificate, wire up RBAC, take a
node out for maintenance and run a static pod.

---

## ▶️ Getting started

```bash
# from the host (lab-setup/)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-cluster-maintenance/setup.sh"   # seed the lab
vagrant ssh cp1                                                            # work on cp1
#   … perform the 8 tasks …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-cluster-maintenance/grade.sh"   # grade yourself
```

> ℹ️ **Notes on this environment**
> - There is **no `etcdctl` on the host**. Exec into the etcd pod instead:
>   `kubectl -n kube-system exec etcd-cp1 -- etcdctl …` (the image also ships `etcdutl`).
>   The etcd pod mounts the host's `/var/lib/etcd`, so files written there appear on cp1.
> - You have **passwordless `sudo`** on cp1.
> - Tasks are independent **except T2**, which needs the backup from **T1**.

---

## 🗄️ etcd Backup & Restore (26 pts)

### Task 1 — Back up etcd (14 pts)
Save a snapshot of the cluster's etcd database to **`/var/lib/etcd/etcd-backup.db`**.
Use the etcd server certificates under `/etc/kubernetes/pki/etcd/` and endpoint
`https://127.0.0.1:2379`. The snapshot must be a **valid** etcd snapshot.

### Task 2 — Verify the backup by restoring it (12 pts) · *depends on Task 1*
Restore the snapshot from Task 1 into a **new** data directory **`/var/lib/etcd/restore`**
(do **not** touch the live etcd). A restored member directory must exist under it.

---

## 🔐 Certificates & CSR (24 pts)

### Task 3 — Approve a certificate request (12 pts)
A `CertificateSigningRequest` named **`applicant`** is **Pending**. Approve it so that a
client certificate is issued (its `.status.certificate` becomes populated).

### Task 6 — Report a certificate's expiry (12 pts)
Find the expiration date of the **kube-apiserver** certificate and write **that date**
(exactly as reported by `kubeadm`) into the file **`/opt/cka/apiserver-expiration.txt`**.

> 💡 The `kubeadm certs check-expiration` command lists every managed certificate.

---

## 👤 RBAC & Authorization (26 pts)

### Task 4 — Cluster-wide read-only access (14 pts)
Create a **ClusterRole** named **`pod-viewer`** allowing `get`, `list`, `watch` on **pods**,
and bind it (**ClusterRoleBinding** `pod-viewer-binding`) to the **group `viewers`**.
Members of `viewers` must be able to list pods in **every** namespace, but **not delete** them.

> 💡 Verify with `kubectl auth can-i … --as=<user> --as-group=viewers`.

### Task 5 — Namespaced configmap management (12 pts)
In namespace **`finance`**, grant the user **`auditor`** the ability to manage **ConfigMaps**
(`get`, `list`, `create`, `update`). The grant must apply **only** in `finance` — `auditor`
must **not** be able to create ConfigMaps in any other namespace.

---

## 🖥️ Nodes & Static Pods (24 pts)

### Task 7 — Drain a node for maintenance (12 pts)
Node **`w1`** must be taken out of service for maintenance: **cordon it and evict its
workloads** (a Deployment `legacy-app` is currently running there). Afterwards `w1` must be
`SchedulingDisabled` and carry no `legacy-app` pods.

> 💡 DaemonSet pods are expected to remain — the standard drain flags handle them.

### Task 8 — Run a static pod (12 pts)
Create a **static pod** named **`web-static`** on **cp1** using image **`nginx:1.29-alpine`**
(container port 80). It must end up **Running** and be managed by the kubelet (not the API).

> 💡 Remember where the kubelet reads static-pod manifests, and how the mirror pod is named.

---

## 📌 Out of scope (destructive, one-shot)
Two classic domain-01 operations are **not** auto-graded because they are irreversible on a
shared cluster — see `solutions/SOLUTIONS.md` for how they are done:
- **Live etcd restore** (stopping the API server and repointing etcd at a restored data-dir).
- **`kubeadm upgrade apply`** of the control plane.

---

## ✅ Grading
`grade.sh` is read-only and prints a PASS/FAIL per task, a subtotal per section and a score
out of **100** (target **≥ 75 %**). Re-running `setup.sh` resets the lab to its initial state.
