# 📦 Lab — Workloads & Scheduling

> **CKA domain 02 — Workloads & Scheduling (15%).**
> A **build** lab: you author the objects and grade the *result*.
> **100 pts · target ≥ 75 %.** All work is done **on cp1**. **Estimated time: ~1 h – 1 h 30** (13 tasks).

You will create Deployments and control a rollout, run a DaemonSet / Job / CronJob, add an
HPA, tune QoS, and place pods precisely with `nodeSelector`, `nodeAffinity`, taints &
tolerations, topology spread and a PriorityClass.

---

## ▶️ Getting started

```bash
# from the host (lab-setup/)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-workloads-scheduling/setup.sh"   # seed the lab
vagrant ssh cp1                                                             # work on cp1
#   … build the 13 objects …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-workloads-scheduling/grade.sh"   # grade yourself
```

> ℹ️ **Notes**
> - Cluster nodes: **cp1** (control-plane, tainted), **w1**, **w2** (workers).
> - Use `nginx:1.29-alpine` for web pods and `busybox:1.36` for batch tasks.
> - Speed tip: `kubectl create … --dry-run=client -o yaml > f.yaml`, edit, `kubectl apply -f f.yaml`.

---

## 📦 Deployments & Rollouts (21 pts)

### Task 1 — Deployment and scale (6 pts)
In namespace **`w-deploy`**, create a Deployment **`frontend`** using **`nginx:1.29-alpine`**
and **scale it to 3** replicas (all Ready).

### Task 2 — Rollout strategy (6 pts)
In namespace **`w-deploy`**, create a Deployment **`rollout-app`** (`nginx:1.29-alpine`,
replica count of your choice) whose update strategy is **RollingUpdate** with
**`maxSurge: 2`** and **`maxUnavailable: 0`** (a zero-downtime rollout).
*Graded on the strategy only.*

### Task 3 — Rolling update & rollback (9 pts)
In namespace **`w-roll`**, create a Deployment **`rollver`** with image **`nginx:1.29-alpine`**
and **2 replicas**, then:

1. **update** the image to **`nginx:1.29`** (rolling update — wait for it to complete);
2. **roll back** to the previous revision.

Final state: image **`nginx:1.29-alpine`** again, **2/2 Ready**, and the rollout history
shows **at least 3 revisions**.

> 💡 `kubectl set image` · `kubectl rollout status` · `kubectl rollout undo` · `kubectl rollout history`.
> The container created by `kubectl create deploy` is named after the image (**`nginx`**).

---

## ⏱️ DaemonSets, Jobs & CronJobs (22 pts)

### Task 4 — DaemonSet on every node (8 pts)
In namespace **`w-ds`**, create a DaemonSet **`node-agent`** (`nginx:1.29-alpine`) that runs
on **all three nodes** — including the tainted control-plane **cp1** and worker **w1**
(which you will taint in Task 11). It must report **`numberReady: 3`**.

> 💡 A DaemonSet only lands on nodes whose taints it **tolerates**.

### Task 5 — Job with repeated completions (7 pts)
In namespace **`w-batch`**, create a Job **`pi`** (`busybox:1.36`) that must complete
**3 times** (`completions: 3`) — `.status.succeeded` reaches 3.

### Task 6 — CronJob (7 pts)
In namespace **`w-batch`**, create a CronJob **`report`** (`busybox:1.36`) with schedule
**`*/1 * * * *`** (every minute). *Graded on the spec — you need not wait for it to fire.*

---

## 📈 Autoscaling & QoS (17 pts)

### Task 7 — HorizontalPodAutoscaler (9 pts)
A Deployment **`hpa-target`** already exists in namespace **`w-hpa`** (its pods declare CPU
requests). Create an **HPA `hpa-target`** for it: **min 1**, **max 5**, target **CPU 50 %**.

### Task 8 — Guaranteed QoS (8 pts)
In namespace **`w-res`**, create a pod **`guaranteed`** (`nginx:1.29-alpine`) whose QoS class
is **Guaranteed**.

> 💡 Guaranteed requires CPU **and** memory `requests` **equal** to the `limits`.

---

## 🎯 Scheduling & Placement (40 pts)

### Task 9 — nodeSelector (7 pts)
Label node **w2** with **`disktype=ssd`**, then create a pod **`ssd-pod`** (`nginx:1.29-alpine`)
in namespace **`w-sched`** that uses a **nodeSelector** to run **on w2**.

### Task 10 — nodeAffinity (7 pts)
In namespace **`w-sched`**, create a pod **`affinity-pod`** (`nginx:1.29-alpine`) that uses
**required `nodeAffinity`** on `kubernetes.io/hostname` to run **on w2**.

### Task 11 — Taint & toleration (9 pts)
**Taint** node **w1** with **`dedicated=batch:NoSchedule`**, then create a pod **`batch-pod`**
(`nginx:1.29-alpine`) in namespace **`w-taint`** that **tolerates** this taint and actually
**runs on w1**.

> 💡 The pod must both *tolerate* the taint and *target* w1. Do not use `nodeName` — that
> bypasses the scheduler (and the taint) and would defeat the exercise.

### Task 12 — Topology spread (8 pts)
In namespace **`w-spread`**, create a Deployment **`spread-app`** (`nginx:1.29-alpine`,
replica count of your choice) whose pod template has a **topologySpreadConstraint**:
`maxSkew: 1`, `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: ScheduleAnyway`.
*Graded on the spec only.*

### Task 13 — PriorityClass (9 pts)
Create a **PriorityClass `high-priority`** with value **`1000000`**, then run a pod
**`critical`** (`nginx:1.29-alpine`) in namespace **`w-prio`** that uses it (and is **Running**).

---

## ✅ Grading
`grade.sh` is read-only and prints a PASS/FAIL per task, a subtotal per section and a score
out of **100** (target **≥ 75 %**). Re-running `setup.sh` resets the lab to its initial state.
