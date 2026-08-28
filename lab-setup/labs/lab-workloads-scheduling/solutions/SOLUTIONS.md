# 📦 Lab — Workloads & Scheduling · SOLUTIONS

> One valid path per task. The grader checks the **result** (replicas ready, strategy,
> QoS class, placement, HPA spec…), not the exact commands. Everything runs **on cp1**.
> Tip: `kubectl create … --dry-run=client -o yaml > f.yaml` then edit is faster than typing YAML.

---

## 📦 Deployments & Rollouts

### T1 — Deployment `frontend` scaled to 3 (ns `w-deploy`)
```bash
kubectl -n w-deploy create deployment frontend --image=nginx:1.29-alpine --replicas=1
kubectl -n w-deploy scale deployment frontend --replicas=3
kubectl -n w-deploy get deploy frontend        # READY 3/3
```

### T2 — RollingUpdate strategy (ns `w-deploy`)
```bash
kubectl -n w-deploy create deployment rollout-app --image=nginx:1.29-alpine --replicas=3
kubectl -n w-deploy patch deployment rollout-app --type=merge -p '{
  "spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":2,"maxUnavailable":0}}}}'
kubectl -n w-deploy get deploy rollout-app -o jsonpath='{.spec.strategy.rollingUpdate}{"\n"}'
```
**Key points**: `maxSurge=2` lets 2 extra pods spin up during an update; `maxUnavailable=0`
guarantees no capacity loss — a zero-downtime rollout.

---

## ⏱️ DaemonSets, Jobs & CronJobs

### T3 — DaemonSet on every node incl. cp1 and a tainted w1 (ns `w-ds`)
A DaemonSet only lands on a node whose taints it **tolerates**. To cover the control-plane
node *and* w1 (tainted in T10), tolerate **all** taints with `operator: Exists`.
```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: w-ds }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
      - operator: Exists            # tolerate every taint -> runs on all 3 nodes
      containers:
      - name: agent
        image: nginx:1.29-alpine
EOF
kubectl -n w-ds get ds node-agent    # DESIRED 3  READY 3
```

### T4 — Job with 3 completions (ns `w-batch`)
```bash
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: { name: pi, namespace: w-batch }
spec:
  completions: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: pi
        image: busybox:1.36
        command: ["sh","-c","echo done"]
EOF
kubectl -n w-batch get job pi        # COMPLETIONS 3/3
```

### T5 — CronJob every minute (ns `w-batch`)
```bash
kubectl -n w-batch create cronjob report \
  --image=busybox:1.36 --schedule="*/1 * * * *" -- sh -c "date"
kubectl -n w-batch get cronjob report
```

---

## 📈 Autoscaling & QoS

### T6 — HorizontalPodAutoscaler (ns `w-hpa`)
The Deployment `hpa-target` already exists (with CPU **requests** — mandatory for CPU HPA).
```bash
kubectl -n w-hpa autoscale deployment hpa-target --cpu=50% --min=1 --max=5
kubectl -n w-hpa get hpa hpa-target
```
> On older clients use `--cpu-percent=50` (now deprecated in favour of `--cpu=50%`).
**Key points**: the HPA gets the deployment's name (`hpa-target`). Without CPU `requests`
on the pods, the autoscaler cannot compute a utilisation percentage.

### T7 — Guaranteed QoS pod (ns `w-res`)
QoS is **Guaranteed** only when every container sets CPU **and** memory `requests` **equal**
to its `limits`.
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: guaranteed, namespace: w-res }
spec:
  containers:
  - name: app
    image: nginx:1.29-alpine
    resources:
      requests: { cpu: 100m, memory: 64Mi }
      limits:   { cpu: 100m, memory: 64Mi }
EOF
kubectl -n w-res get pod guaranteed -o jsonpath='{.status.qosClass}{"\n"}'   # Guaranteed
```

---

## 🎯 Scheduling & Placement

### T8 — nodeSelector onto w2 (ns `w-sched`)
```bash
kubectl label node w2 disktype=ssd
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: ssd-pod, namespace: w-sched }
spec:
  nodeSelector: { disktype: ssd }
  containers:
  - name: app
    image: nginx:1.29-alpine
EOF
kubectl -n w-sched get pod ssd-pod -o wide     # NODE w2
```

### T9 — nodeAffinity onto w2 (ns `w-sched`)
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: affinity-pod, namespace: w-sched }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values: ["w2"]
  containers:
  - name: app
    image: nginx:1.29-alpine
EOF
kubectl -n w-sched get pod affinity-pod -o wide   # NODE w2
```
**Key points**: `nodeAffinity` is the expressive successor to `nodeSelector` (operators
`In`, `NotIn`, `Exists`…). `required…` is a hard constraint (like nodeSelector).

### T10 — Taint w1, run a tolerating pod there (ns `w-taint`)
```bash
kubectl taint node w1 dedicated=batch:NoSchedule
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: batch-pod, namespace: w-taint }
spec:
  nodeSelector: { kubernetes.io/hostname: w1 }   # aim at w1…
  tolerations:                                    # …and tolerate its taint
  - key: dedicated
    value: batch
    effect: NoSchedule
  containers:
  - name: app
    image: nginx:1.29-alpine
EOF
kubectl -n w-taint get pod batch-pod -o wide     # NODE w1, Running
```
**Key points**: a `NoSchedule` taint **repels** pods that lack a matching toleration.
The pod schedules on w1 only because it *both* tolerates the taint and targets w1.
(Setting `nodeName` would bypass the scheduler and the taint entirely — that would not
demonstrate the toleration.)

### T11 — topologySpreadConstraints (ns `w-spread`)
```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: spread-app, namespace: w-spread }
spec:
  replicas: 2
  selector: { matchLabels: { app: spread-app } }
  template:
    metadata: { labels: { app: spread-app } }
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector: { matchLabels: { app: spread-app } }
      containers:
      - name: app
        image: nginx:1.29-alpine
EOF
```
**Key points**: `maxSkew=1` keeps the pod count per node within 1. `ScheduleAnyway` makes it
a *soft* preference (pods still schedule even if the spread can't be honoured — important
here since w1 is tainted). `DoNotSchedule` would make it a hard rule.

### T12 — PriorityClass + critical pod (ns `w-prio`)
```bash
kubectl apply -f - <<'EOF'
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: high-priority }
value: 1000000
globalDefault: false
description: "Critical workloads"
---
apiVersion: v1
kind: Pod
metadata: { name: critical, namespace: w-prio }
spec:
  priorityClassName: high-priority
  containers:
  - name: app
    image: nginx:1.29-alpine
EOF
kubectl -n w-prio get pod critical -o jsonpath='{.spec.priority}{"\n"}'   # 1000000
```
**Key points**: a higher `value` schedules first and, under pressure, can **preempt**
lower-priority pods.

---

## 🧭 General method
- Generate YAML fast: `kubectl create deploy/job/cronjob … --dry-run=client -o yaml`.
- Verify placement with `-o wide` (the `NODE` column) and QoS/priority with `jsonpath`.
- Scheduling constraints (nodeSelector, affinity, taints/tolerations, topology spread) are
  the heart of domain 02 — always confirm *where* a pod landed, not just that it's Running.
