# 🔧 Lab — Cross-cutting Troubleshooting (all domains)

> **Themed lab** (not a mock exam): **pure troubleshooting**. At the start **everything is broken** —
> it's up to you to **diagnose and fix**. The **18 breakages** cover **all 4 technical domains** of the CKA
> (Architecture/Nodes, Workloads/Scheduling, Services/Networking, Storage): the point is precisely that
> *troubleshooting is cross-cutting*.
> **100 pts**, target **≥ 75 %**. No time limit — this is a practice lab. **Estimated time: ~1 h 30 – 2 h** (18 breakages).

> 🧩 **Independence**: each breakage lives in **its own namespace** (`ts-arch`, `ts-nodes`, `ts-work`,
> `ts-net`, `ts-netpol`, `ts-storage`) — you can tackle **just one** without breaking the others. **Two
> exceptions** involve the **node** and are flagged: **A2** is fixed **on `cp1`** (`vagrant ssh cp1`,
> static manifest), **A3** concerns the state of node **`w1`** (fixable via `kubectl`). No task
> depends on another.

> 🔎 **Everything is checked live**: the grader reads the **real status** (`Running`, `Bound`, endpoints) and
> **`exec`s** into the Pods to test **traffic** (services, NetworkPolicy) and **DNS**. It never
> shows the solution, only the observed **symptom**.

## Getting started
```bash
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/setup.sh"   # breaks the environment (idempotent)
# … you fix the breakages …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/grade.sh"   # grade yourself (read-only)
```
> `setup.sh` is **idempotent**: it **first undoes** any repair from a previous run (nodes
> uncordoned/un-tainted, static manifest removed from `cp1`, finalizers cleared), recreates the namespaces
> and re-seeds the **broken** state. The solutions are in [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — open it only afterwards.

> 🧭 **Method** (recap [sheet 05](../../../05-troubleshooting.md)): `describe` → **Events** first;
> `logs` / `logs -p`; `Pending` ⇒ `describe pod` (resources / taint / nodeSelector / cordon);
> "no traffic" ⇒ `get endpoints` (selector/probes), `targetPort`, NetworkPolicy, DNS; node ⇒ `describe node`.

---

## 🏛️ Domain ARCH — Cluster Architecture & Nodes (25 pts)

### A1 — RBAC: a ServiceAccount with no permissions (7 pts) · ns `ts-arch`
The *ServiceAccount* **`deploy-bot`** must be able to **list** (`get`/`list`) the Pods in `ts-arch`, but
`kubectl auth can-i` returns **`no`**. Yet the *Role* and the *RoleBinding* both exist. Fix the binding.

> 💡 `kubectl -n ts-arch auth can-i list pods --as=system:serviceaccount:ts-arch:deploy-bot`.
> Compare the RoleBinding **subject** to the real SA.
> Goal: `deploy-bot` can **`list`** pods but **not `delete`** (don't over-grant).

### A2 — Static pod broken on `cp1` (7 pts) · ns `default` · **on node `cp1`**
The static pod **`ts-static-cp1`** (in `default`) fails to start. Fix it **on node
`cp1`** so it goes `Running`.

> 💡 `kubectl describe pod ts-static-cp1`. A static pod is fixed **in `/etc/kubernetes/manifests/`
> on the node** (not via `kubectl`). The kubelet reloads it on its own.
> Goal: `ts-static-cp1` **`Running`** with a valid image.

### A3 — Node `w1` "out of service" (7 pts) · ns `ts-nodes`
The *Deployment* **`billing`** (namespace `ts-nodes`) stays at **0 available**: its pods are pinned to
`w1`, but **`w1` is under maintenance**. Bring the service back up.

> 💡 `kubectl -n ts-nodes describe pod -l app=billing` then `kubectl describe node w1`. There may be
> **several stacked blockers** on the node. (Taint effects: `NoSchedule` / `PreferNoSchedule` / `NoExecute`.)
> Goal: `billing` has **≥ 1 available replica**.

### A4 — Object stuck in `Terminating` (4 pts) · ns `ts-arch`
The *ConfigMap* **`stuck-cm`** in `ts-arch` was deleted but stays **`Terminating`** indefinitely.
Make it **actually disappear**.

> 💡 `kubectl -n ts-arch get cm stuck-cm -o yaml` → look at `metadata.finalizers` + `deletionTimestamp`.
> Goal: `stuck-cm` no longer exists.

---

## 📦 Domain WORK — Workloads & Scheduling (40 pts) · ns `ts-work`

### W1 — `ImagePullBackOff` (5 pts)
The *Deployment* **`web`** won't start (image not found). Fix it.
> 💡 `describe deploy web`. Goal: `web` **available** (≥ 1 replica, valid image).

### W2 — `CrashLoopBackOff` (5 pts)
The *Pod* **`crasher`** keeps restarting. Make it stay `Running`.
> 💡 `kubectl -n ts-work logs crasher -p`. The container's command is the cause.
> Goal: `crasher` **`Running`** (stable).

### W3 — `CreateContainerConfigError` (6 pts)
The *Pod* **`checkout`** fails to create its container: it injects `DB_PASSWORD` from a *Secret*, but
**a key is missing**. Fix it so it starts with the variable present (**non-empty** value).
> 💡 `describe pod checkout` (Events). Goal: `checkout` **`Running`** with `DB_PASSWORD` properly injected (non-empty).

### W4 — `Pending` (resources) (5 pts)
The *Pod* **`report`** stays `Pending`: nothing can host it. Make it `Running`.
> 💡 `describe pod report` → `Insufficient memory/cpu`. Goal: `report` **`Running`**.

### W5 — `Pending` (placement constraint) (5 pts)
The *Pod* **`analytics`** stays `Pending` because of a **placement constraint** that no node
satisfies. Make it `Running`.
> 💡 `describe pod analytics` → `didn't match node selector`. Goal: `analytics` **`Running`**.

### W6 — Pods `Running` but never `Ready` (4 pts)
The *Deployment* **`frontend`** has its pods `Running` but **`0/1 READY`** — so no traffic. Fix the
cause so they become `Ready`.
> 💡 `describe pod -l app=frontend` → `Readiness` section. Goal: `frontend` has **≥ 1 Ready replica**.

### W7 — `OOMKilled` (5 pts)
The *Pod* **`cruncher`** crash-loops: the app legitimately holds **~50 MiB** in memory
(`/dev/shm`), but its **memory limit** is far too low. **Recreate** it with an adequate
memory limit (e.g. **128Mi** — keep a limit, don't remove it). It must end up **Running
and Ready with 0 restarts**.
> 💡 `describe pod cruncher` → `container init was OOM-killed (memory limit too low?)`.
> tmpfs (`/dev/shm`) pages **count against the pod's memory limit** — and they survive
> container restarts. Pod resources are **immutable**: export the YAML, fix the limit,
> `kubectl replace --force -f`.
> Goal: `cruncher` **Running/Ready**, **0 restarts**, with a memory limit still set.

### W8 — Crash caused by the `securityContext` (5 pts)
The *Pod* **`locked-web`** (nginx) **crash-loops at startup**: its securityContext forces a
user the image cannot run as. Fix the Pod so nginx starts — **keep the image
`nginx:1.29-alpine`**.
> 💡 `kubectl -n ts-work logs locked-web` → `permission denied` on nginx's working dirs.
> The pod-level securityContext is **immutable** → recreate without the offending `runAsUser`
> (or as root). Goal: `locked-web` **Running/Ready** with the same image.

---

## 🌐 Domain NET — Services & Networking (23 pts)

### N1 — Service with no endpoints (6 pts) · ns `ts-net`
The *Service* **`api-svc`** has **no endpoints** even though the `api` Deployment is running. Restore them.
> 💡 `kubectl -n ts-net get endpoints api-svc` + `get pods --show-labels`.
> Goal: `api-svc` has **≥ 1 endpoint**.

### N2 — Service that doesn't route (6 pts) · ns `ts-net`
The *Service* **`shop-svc`** does have endpoints, but a `wget` from **`shop-client`** fails. Fix
the routing.
> 💡 `kubectl -n ts-net exec shop-client -- wget -T4 -qO- http://shop-svc`. Compare `port`/`targetPort` to the container's real port.
> Goal: `shop-client` **reaches** `shop-svc`.

### N3 — Traffic blocked by a NetworkPolicy (6 pts) · ns `ts-netpol`
In `ts-netpol`, the Pod **`client`** can no longer reach **`backend`**: a *NetworkPolicy* blocks everything.
Allow the **`client → backend`** flow (without re-opening everything).
> 💡 `kubectl -n ts-netpol get netpol`; test `kubectl -n ts-netpol exec client -- wget -T4 -qO- http://backend`.
> Goal: `client` **reaches** `backend` (traffic flows).

### N4 — Broken DNS resolution (5 pts) · ns `ts-net`
The *Pod* **`dns-broken`** resolves **no** cluster service (`*.svc.cluster.local`). Fix its
DNS resolution.
> 💡 `kubectl -n ts-net exec dns-broken -- nslookup kubernetes.default`; look at `spec.dnsPolicy`.
> Goal: `dns-broken` **resolves** `kubernetes.default.svc.cluster.local`.

---

## 💾 Domain STO — Storage (12 pts) · ns `ts-storage`

### S1 — PVC stuck in `Pending` (6 pts)
The *PVC* **`data`** stays `Pending`: it can't find a volume. Make it **bind**.
> 💡 `describe pvc data`. A PV `pv-small` exists — compare its `storageClassName` to the requested one.
> Goal: `data` is **`Bound`**.

### S2 — Pod stuck: missing PVC (6 pts)
The *Pod* **`app`** stays in `ContainerCreating`: it mounts a PVC that **doesn't exist**. Fix it so it
starts (a PV `pv-app` is available).
> 💡 `describe pod app` → `persistentvolumeclaim "…" not found`.
> Goal: `app` **`Running`**.

---

> 🧪 This lab is **extensible**: other classic breakages (kubelet `NotReady`, `etcd`/certificates,
> CoreDNS `Corefile`, `kube-proxy`) require **system** access to the workers and are covered in the
> **mock exams** (`lab-setup/mock-exam/`). Here, everything is fixable from `cp1` + `kubectl`.
