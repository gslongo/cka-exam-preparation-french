# 🧪 CKA — Mock exam #4 · SOLUTIONS (killer.sh drills — session 2)

> One valid path per task. The grader checks the **result**, not the exact commands.
> Open this file **only after** grading yourself.

---

## 🌐 DNS & Service discovery

### T1 — Service & Pod DNS FQDNs (ns `q4-control` / `q4-workload`)
```bash
# Which ConfigMap does the Deployment use?
kubectl -n q4-control get deploy controller -o jsonpath='{.spec.template.spec.containers[0].envFrom}{"\n"}'

kubectl -n q4-control edit configmap controller-config
#   DNS_1: kubernetes.default.svc.cluster.local
#   DNS_2: department.q4-workload.svc.cluster.local
#   DNS_3: section100.section.q4-workload.svc.cluster.local
#   DNS_4: 1-2-3-4.kube-system.pod.cluster.local

# Env vars sourced from a ConfigMap are frozen at container start → restart the Pods:
kubectl -n q4-control rollout restart deploy controller
kubectl -n q4-control rollout status  deploy controller

# Verify from inside a controller Pod:
kubectl -n q4-control exec deploy/controller -- sh -c 'echo $DNS_1; nslookup $DNS_1'
```
**Key points**:
- *Service*: `<svc>.<ns>.svc.cluster.local` — the FQDN form is identical for a **headless**
  Service (it just resolves to the Pod IPs instead of a ClusterIP).
- *Stable Pod name*: a Pod with `hostname: section100` + `subdomain: section` (matching a
  headless Service **`section`** — a different one than `department`!) gets
  `<hostname>.<subdomain>.<ns>.svc.cluster.local` — **independent of its IP**. The
  `<ip-dashed>.<ns>.pod.cluster.local` form would break on every IP change.
- *Pod by IP*: dashes replace the dots → `1-2-3-4.kube-system.pod.cluster.local`.
- ConfigMap-sourced **env vars never refresh in place** → `rollout restart` is part of the answer.

---

## 🏛️ Static Pods & Services

### T2 — Static Pod exposed by a NodePort (ns `default`, on `cp1`)
```bash
# 1. Generate the manifest (kubectl run gives it the label run=my-static-pod):
kubectl run my-static-pod --image=nginx:1-alpine --port=80 \
  --dry-run=client -o yaml > /tmp/my-static-pod.yaml
#    edit /tmp/my-static-pod.yaml — add under the container:
#      resources:
#        requests: { cpu: 10m, memory: 20Mi }

# 2. Drop it into the kubelet's static-pod directory on cp1:
sudo cp /tmp/my-static-pod.yaml /etc/kubernetes/manifests/
kubectl -n default get pod my-static-pod-cp1        # mirror pod, Running

# 3. Expose it — 'expose pod' reuses the Pod's labels as selector:
kubectl -n default expose pod my-static-pod-cp1 --name=static-pod-service \
  --type=NodePort --port=80

# 4. Verify:
kubectl -n default get endpoints static-pod-service          # 1 address
NP=$(kubectl -n default get svc static-pod-service -o jsonpath='{.spec.ports[0].nodePort}')
curl "192.168.56.10:${NP}"                                   # nginx welcome page
```
**Key points**: a static Pod is created by a **manifest file** in `/etc/kubernetes/manifests/`
(the kubelet watches it); the API only shows a read-only **mirror Pod** suffixed with the node
name (`-cp1`). The Service finds it through **labels** like any Pod — that's why the manifest
must carry some (`kubectl run` adds `run=my-static-pod`). NodePort makes it reachable on
**every node IP** at the allocated port (30000-32767 by default).

---

## 🔐 Kubelet certificates

### T3 — Kubelet client & server certificate info (on `w1`, report on `cp1`)
```bash
# On w1 (from the host: vagrant ssh w1):
sudo ls /var/lib/kubelet/pki/
#   kubelet-client-current.pem  ← CLIENT cert (rotated symlink)
#   kubelet.crt                 ← SERVER (serving) cert

sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem \
  -noout -issuer -ext extendedKeyUsage
#   issuer=CN = kubernetes                ← signed by the CLUSTER CA (TLS bootstrapping)
#   TLS Web Client Authentication

sudo openssl x509 -in /var/lib/kubelet/pki/kubelet.crt \
  -noout -issuer -ext extendedKeyUsage
#   issuer=CN = w1-ca@<timestamp>         ← SELF-signed by a per-node CA
#   TLS Web Server Authentication

# On cp1 — write the four values:
cat > /opt/exam-04/certificate-info.txt <<'EOT'
Kubelet client certificate:
  Issuer: CN = kubernetes
  Extended Key Usage: TLS Web Client Authentication
Kubelet server certificate:
  Issuer: CN = w1-ca@<timestamp>
  Extended Key Usage: TLS Web Server Authentication
EOT
#   (paste the real w1-ca@… value shown by openssl)
```
**Key points**: with kubeadm **TLS bootstrapping**, the kubelet's **client** cert is issued by
the **cluster CA** (issuer `CN = kubernetes`) through the CSR API, and
`kubelet-client-current.pem` is a **symlink** that enables rotation. The **serving** cert, by
default, is **self-signed** by a throwaway per-node CA (`<node>-ca@<timestamp>`) — that's why
the apiserver needs `--kubelet-certificate-authority` or skips verification; signing it via the
cluster CA requires `serverTLSBootstrap: true`. EKU tells the role: **clientAuth** vs
**serverAuth**.

---

## 🩺 Probes

### T4 — Readiness depending on another Service (ns `default`)
```bash
kubectl run ready-if-service-ready --image=nginx:1-alpine --dry-run=client -o yaml > /tmp/t4.yaml
```
Add the probes to the container:
```yaml
    livenessProbe:
      exec:
        command: ["true"]
    readinessProbe:
      exec:
        command: ["sh", "-c", "wget -T2 -O- http://service-am-i-ready:80"]
```
```bash
kubectl apply -f /tmp/t4.yaml
kubectl get pod ready-if-service-ready        # Running but 0/1 (readiness fails)

# Second pod — its label matches the Service selector:
kubectl run am-i-ready --image=nginx:1-alpine --labels="id=cross-server-ready"

kubectl get endpoints service-am-i-ready      # now 1 address
kubectl get pod ready-if-service-ready        # 1/1 Ready after the next probe period
```
**Key points**: readiness failing keeps the Pod **Running but out of every Service's
endpoints** — liveness would restart it instead. The `wget` resolves the Service by DNS and
only succeeds once `service-am-i-ready` has endpoints, i.e. once a Pod with
`id=cross-server-ready` is **Ready**. The probe command runs **inside** the container — the
image must ship it (nginx:alpine has `wget` via BusyBox).

---

## 📋 kubectl — sorting

### T5 — Sorted Pod listings
```bash
cat > /opt/exam-04/find_pods.sh <<'EOT'
kubectl get pods -A --sort-by=.metadata.creationTimestamp
EOT

cat > /opt/exam-04/find_pods_uid.sh <<'EOT'
kubectl get pods -A --sort-by=.metadata.uid
EOT

bash /opt/exam-04/find_pods.sh       # sanity check — the grader executes them too
bash /opt/exam-04/find_pods_uid.sh
```
**Key points**: `--sort-by` takes a **JSONPath** into the object (`.metadata.…`); combine it
with `-A` for all namespaces. Classic variants: `--sort-by=.status.startTime`,
`--sort-by=.spec.capacity.storage` (PVs). It sorts the **table output**, no `sort` pipe needed.

---

## 🔧 Node troubleshooting

### T6 — Broken kubelet on cp1
```bash
sudo systemctl status kubelet          # inactive (dead) — and on start: status=203/EXEC
sudo systemctl start kubelet
sudo journalctl -u kubelet -e --no-pager | tail -5
#   … Unable to locate executable /usr/local/bin/kubelet: No such file or directory

# Where does that wrong path come from? Inspect EVERY unit file + drop-in:
systemctl cat kubelet
#   … /etc/systemd/system/kubelet.service.d/99-kubeadm-extra.conf overrides ExecStart
#     with /usr/local/bin/kubelet — the real binary is /usr/bin/kubelet (which kubelet)

# Fix: correct the path in the drop-in (or delete the rogue drop-in entirely)
sudo sed -i 's|/usr/local/bin/kubelet|/usr/bin/kubelet|' \
  /etc/systemd/system/kubelet.service.d/99-kubeadm-extra.conf
sudo systemctl daemon-reload
sudo systemctl restart kubelet
sudo systemctl is-active kubelet       # active
kubectl get node cp1                   # Ready (allow ~30 s for the heartbeat)

kubectl run success --image=nginx:1-alpine
kubectl get pod success -o wide        # Running
```
**Key points**: kubelet is a **systemd service**, not a Pod — debug it with `systemctl` /
`journalctl`, never `kubectl`. `systemctl cat` shows the unit **plus all drop-ins** in load
order (later files override `ExecStart`). `status=203/EXEC` = the binary path is wrong
(`which kubelet` gives the real one). After the fix: `daemon-reload` **then** `restart`.

---

## 🗄️ etcd operations

### T7 — etcd version & snapshot (on `cp1`)
```bash
# 1. Version — the etcd binary only exists inside the etcd Pod:
kubectl -n kube-system exec etcd-cp1 -- etcd --version > /opt/exam-04/etcd-version

# 2. Snapshot — write under /var/lib/etcd (hostPath shared with cp1), then move it:
kubectl -n kube-system exec etcd-cp1 -- etcdctl snapshot save /var/lib/etcd/snap.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
sudo mv /var/lib/etcd/snap.db /opt/exam-04/etcd-snapshot.db

# Verify:
sudo cp /opt/exam-04/etcd-snapshot.db /var/lib/etcd/check.db
kubectl -n kube-system exec etcd-cp1 -- etcdutl snapshot status /var/lib/etcd/check.db -w table
sudo rm /var/lib/etcd/check.db
```
**Key points**: `snapshot save` is an **online** operation against `:2379` and needs the
**etcd server certs** (mTLS). The etcd static Pod mounts `/var/lib/etcd` and
`/etc/kubernetes/pki/etcd` from the host — that's the bridge for files in both directions.
`etcd --version` ≠ `etcdctl version` (server vs client binaries).

---

## 🏛️ Control plane components

### T8 — How is each component started? (on `cp1`)
```bash
# kubelet: systemd service (a plain OS process)
systemctl status kubelet | head -3

# apiserver / scheduler / controller-manager / etcd: static-pod manifests
ls /etc/kubernetes/manifests/
#   etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml
kubectl -n kube-system get pods -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind | grep -E 'apiserver|scheduler|controller|etcd'
#   owner = Node → mirror pods of static pods

# DNS: a Deployment (regular pods, owner = ReplicaSet) named coredns
kubectl -n kube-system get deploy,pods -l k8s-app=kube-dns

cat > /opt/exam-04/controlplane-components.txt <<'EOT'
kubelet: process
kube-apiserver: static-pod
kube-scheduler: static-pod
kube-controller-manager: static-pod
etcd: static-pod
dns: pod coredns
EOT
```
**Key points**: three start types coexist — **systemd process** (kubelet only), **static pods**
(manifests in `/etc/kubernetes/manifests/`, mirror pods owned by `Node`), and **regular pods**
(CoreDNS via a Deployment/ReplicaSet). Telling them apart: `ownerReferences` (Node vs
ReplicaSet) and the presence of a manifest file / systemd unit.

---

## 🧠 Scheduler

### T9 — Be the scheduler yourself (on `cp1`)
```bash
# 1. Stop the scheduler REVERSIBLY: park its static-pod manifest outside the watched dir
sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /etc/kubernetes/
kubectl -n kube-system get pods | grep scheduler        # gone after a few seconds

# 2. Pod without scheduler → stays Pending, no node assigned
kubectl run manual-schedule --image=httpd:2-alpine
kubectl get pod manual-schedule -o wide                 # Pending, NODE = <none>

# 3. BE the scheduler: assign the node yourself — nodeName is set at creation,
#    so recreate the Pod with it:
kubectl get pod manual-schedule -o yaml > /tmp/ms.yaml
#    add under spec:      nodeName: cp1
kubectl replace --force -f /tmp/ms.yaml
kubectl get pod manual-schedule -o wide                 # Running on cp1

# 4. Restart the scheduler and prove it works
sudo mv /etc/kubernetes/kube-scheduler.yaml /etc/kubernetes/manifests/
kubectl -n kube-system get pods | grep scheduler        # Running again
kubectl run manual-schedule2 --image=httpd:2-alpine
kubectl get pod manual-schedule2 -o wide                # Running on w1 or w2
```
**Key points**: the scheduler's only job is to write **`spec.nodeName`** on pending Pods —
setting it yourself *is* scheduling (the kubelet of that node takes over). `nodeName` therefore
**bypasses every scheduler check, taints included** — that's why the Pod runs on the tainted
`cp1`. Stopping a static pod = **moving its manifest** out of `/etc/kubernetes/manifests/`
(deleting the mirror pod does nothing). `nodeName` is **immutable** → recreate the Pod to set it.

---

## 💾 Storage — dynamic provisioning

### T10 — StorageClass for a backup Job (ns `q4-backup`)
```bash
# 1. The StorageClass (reclaimPolicy is TOP-LEVEL, no spec block):
kubectl apply -f - <<'EOT'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-backup
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOT

# 2. Edit /opt/exam-04/backup.yaml — add a PVC and swap the emptyDir volume:
#    ---
#    apiVersion: v1
#    kind: PersistentVolumeClaim
#    metadata: { name: backup-pvc, namespace: q4-backup }
#    spec:
#      accessModes: [ReadWriteOnce]
#      storageClassName: local-backup
#      resources: { requests: { storage: 50Mi } }
#    …and in the Job template:
#      volumes:
#      - name: backup
#        persistentVolumeClaim: { claimName: backup-pvc }

kubectl apply -f /opt/exam-04/backup.yaml
# (re-run if needed: kubectl -n q4-backup delete job backup && kubectl apply -f …)

kubectl -n q4-backup get job backup            # COMPLETIONS 1/1
kubectl -n q4-backup get pvc                   # Bound to pvc-<uid>
kubectl get pv                                  # auto-created PV, RECLAIM=Retain
```
**Key points**: with **WaitForFirstConsumer** the PVC stays `Pending` until a Pod consumes it
— the PV only appears when the Job's Pod is scheduled (normal, not a bug). `reclaimPolicy` on
the **SC** is inherited by the provisioned PVs (`Retain` → PV survives PVC deletion as
`Released`). The auto-created PV carries the annotation
`pv.kubernetes.io/provisioned-by: rancher.io/local-path` — that's how « dynamic » is proven.
A Job's template is **immutable**: to re-run it, delete + recreate.

---

## 🔑 Secrets

### T11 — Secret as volume and as env (ns `q4-secret`)
```bash
kubectl create ns q4-secret
# The provided file carries no namespace → apply it into the right one:
kubectl -n q4-secret apply -f /opt/exam-04/secret1.yaml
kubectl -n q4-secret create secret generic secret2 --from-literal=user=user1 --from-literal=pass=1234

kubectl -n q4-secret run secret-pod --image=busybox:1 --dry-run=client -o yaml -- sh -c 'sleep 1d' > /tmp/t11.yaml
```
Add volume, mount and env to the container:
```yaml
    env:
    - name: APP_USER
      valueFrom:
        secretKeyRef: { name: secret2, key: user }
    - name: APP_PASS
      valueFrom:
        secretKeyRef: { name: secret2, key: pass }
    volumeMounts:
    - name: secret1
      mountPath: /tmp/secret1
      readOnly: true
  volumes:
  - name: secret1
    secret: { secretName: secret1 }
```
```bash
kubectl apply -f /tmp/t11.yaml
kubectl -n q4-secret exec secret-pod -- ls /tmp/secret1        # halt
kubectl -n q4-secret exec secret-pod -- env | grep APP_        # APP_USER=user1 APP_PASS=1234
```
**Key points**: two injection modes — **volume** (each key = a file; updates propagate) and
**env** (`secretKeyRef`; frozen at container start). `readOnly: true` on the volumeMount is
asked explicitly. Both Secrets must exist **before** the Pod starts, else
`CreateContainerConfigError`.

---

## 🎯 Scheduling — taints & tolerations

### T12 — Pod restricted to control-plane nodes (ns `default`)
```bash
kubectl get node cp1 -o jsonpath='{.spec.taints}'    # node-role.kubernetes.io/control-plane:NoSchedule
kubectl get node cp1 --show-labels | tr ',' '\n' | grep control-plane   # existing label, value ""

kubectl run pod1 --image=httpd:2-alpine --dry-run=client -o yaml > /tmp/t12.yaml
```
Edit `/tmp/t12.yaml`:
```yaml
spec:
  containers:
  - name: pod1-container            # rename the container
    image: httpd:2-alpine
  tolerations:                      # the RIGHT to land on cp1
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  nodeSelector:                     # the CONSTRAINT to land only there
    node-role.kubernetes.io/control-plane: ""
```
```bash
kubectl apply -f /tmp/t12.yaml
kubectl get pod pod1 -o wide        # Running on cp1
```
**Key points**: the toleration alone lets the Pod go *anywhere* (it only lifts the taint
repulsion); the nodeSelector alone would leave it **Pending** (taint not tolerated). *Only on
control planes* therefore requires **both**. The label `node-role.kubernetes.io/control-plane`
already exists with an **empty value** (`""`) — no new label needed.

---

## 🧭 Multi-container Pods

### T13 — Shared volume & Downward API (ns `default`)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-playground
  namespace: default
spec:
  volumes:
  - name: vol                      # « not persisted, not shared with other Pods » = emptyDir
    emptyDir: {}
  containers:
  - name: c1
    image: nginx:1-alpine
    env:
    - name: MY_NODE_NAME
      valueFrom:
        fieldRef: { fieldPath: spec.nodeName }   # Downward API
    volumeMounts: [{ name: vol, mountPath: /vol }]
  - name: c2
    image: busybox:1
    command: ["sh","-c","while true; do date >> /vol/date.log; sleep 1; done"]
    volumeMounts: [{ name: vol, mountPath: /vol }]
  - name: c3
    image: busybox:1
    command: ["sh","-c","tail -f /vol/date.log"]
    volumeMounts: [{ name: vol, mountPath: /vol }]
```
```bash
kubectl apply -f pod.yaml
kubectl exec multi-container-playground -c c1 -- env | grep MY_NODE_NAME
kubectl logs multi-container-playground -c c3 --tail=3       # dates every second
```
**Key points**: **emptyDir** = pod-lifetime scratch space shared **between containers of the
same Pod** only — exactly « not persisted, not shared with other Pods ». The **Downward API**
(`fieldRef: spec.nodeName`) injects runtime pod metadata as env. The mount paths can differ per
container — what matters is the same **volume name**. `c3` may start before `date.log` exists;
`tail -f` on a shared emptyDir catches up once `c2` writes.

---

## 🔎 Cluster introspection

### T14 — Cluster information file (on `cp1`)
```bash
# 1-2. Nodes:
kubectl get nodes                                          # cp1 control-plane, w1/w2 workers

# 3. Service CIDR = apiserver flag:
sudo grep service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml
#   --service-cluster-ip-range=10.96.0.0/12

# 4. CNI plugin + config:
ls /etc/cni/net.d/                                         # 10-calico.conflist → Calico

# 5. Static pod suffix = the node name:
kubectl -n kube-system get pods | grep '\-cp1'

cat > /opt/exam-04/cluster-info <<'EOT'
# /opt/exam-04/cluster-info
1: 1
2: 2
3: 10.96.0.0/12
4: Calico (/etc/cni/net.d/10-calico.conflist)
5: -cp1
EOT
```
**Key points**: the Service CIDR is nowhere in the API — it's the apiserver flag
`--service-cluster-ip-range` (static-pod manifest). The kubelet reads its CNI config from
**`/etc/cni/net.d/`** (first file in lexical order wins). Mirror pods of static pods are
suffixed with the **node name** (`-cp1`).

---

## 📰 Events & container runtime

### T15 — Watch what the kubelet repairs (on `cp1`)
```bash
# 1. Events script:
cat > /opt/exam-04/cluster_events.sh <<'EOT'
kubectl get events -A --sort-by=.metadata.creationTimestamp
EOT

# 2. Delete the kube-proxy Pod of cp1 (the DaemonSet recreates it):
kubectl -n kube-system get pods -o wide | grep kube-proxy      # find the one on cp1
kubectl -n kube-system delete pod <kube-proxy-cp1-pod>
bash /opt/exam-04/cluster_events.sh | grep kube-proxy > /opt/exam-04/pod_kill.log
#   → Killing, then Scheduled/Pulled/Created/Started for the replacement

# 3. Kill the containerd container (the KUBELET restarts it in place):
sudo crictl ps | grep kube-proxy
sudo crictl rm -f <container-id>
sleep 5
bash /opt/exam-04/cluster_events.sh | grep kube-proxy > /opt/exam-04/container_kill.log
#   → Created/Started again (same Pod, restartCount +1)
```
**Key points**: two different self-healing layers — deleting the **Pod** is repaired by the
**DaemonSet controller** (new Pod, new name), killing the **container** is repaired by the
**kubelet** (same Pod, `restartCount` incremented). `crictl` talks to containerd directly and
needs root; the events tell you exactly who did what.

---

## 🗂️ API resources & Namespaces

### T16 — Namespaced resources & crowded namespace (on `cp1`)
```bash
# 1. All namespaced resources, one name per line:
kubectl api-resources --namespaced -o name > /opt/exam-04/resources.txt

# 2. Count the Roles per project-* namespace:
for ns in $(kubectl get ns -o name | cut -d/ -f2 | grep '^project-'); do
  echo "$ns: $(kubectl -n $ns get roles --no-headers 2>/dev/null | wc -l)"
done
#   project-alpha: 2 · project-beta: 5 · project-gamma: 1 …

echo "project-beta with 5 roles" > /opt/exam-04/crowded-namespace.txt
```
**Key points**: `kubectl api-resources --namespaced` (or `--namespaced=false` for the
cluster-scoped ones); `-o name` prints the plural full name (`roles.rbac.authorization.k8s.io`).
Counting namespaced objects per namespace = a `--no-headers | wc -l` loop — no jq needed.

---

## 🧩 Kustomize & RBAC

### T17 — Operator permissions & new resource via Kustomize (base at `/opt/exam-04/operator`)
```bash
# 1. What does the operator complain about?
kubectl -n q4-operator logs deploy/operator --tail=6
#   ERROR: cannot list teachers.education.cka.local (RBAC forbidden?)
#   ERROR: cannot list courses.education.cka.local (RBAC forbidden?)

# → edit the BASE (not the live object): /opt/exam-04/operator/base/rbac.yaml
#   rules:
#   - apiGroups: ["education.cka.local"]
#     resources: ["students", "teachers", "courses"]
#     verbs: ["get", "list", "watch"]

# 2. New Student in the base — append to base/students.yaml (already in kustomization):
cat >> /opt/exam-04/operator/base/students.yaml <<'EOT'
---
apiVersion: education.cka.local/v1
kind: Student
metadata:
  name: student4
spec: { name: "Dana", description: "fourth student" }
EOT

# 3. Deploy to prod exactly like the original deployment:
kubectl kustomize /opt/exam-04/operator/prod | kubectl apply -f -

kubectl -n q4-operator logs deploy/operator --tail=3     # only OK lines now
kubectl -n q4-operator get students                       # student1..4
```
**Key points**: with Kustomize you fix the **source config**, never the live objects — the
deploy command re-applies base+overlay. In the Role, `resources` are the CRD **plurals** and
`apiGroups` is the CR **group** (`education.cka.local`), not `apiextensions.k8s.io`. RBAC
changes are effective immediately — the operator's next loop succeeds without a restart.
