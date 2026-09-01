# 🛠️ Lab — Cluster Maintenance, etcd & Security · SOLUTIONS

> One valid path per task. The grader checks the **result** (snapshot valid, CSR issued,
> RBAC effective, node drained, static pod Running), not the exact commands.
> Everything runs **on cp1**: `vagrant ssh cp1`.

---

## 🗄️ etcd Backup & Restore

### T1 — Back up etcd
On this cluster there is **no `etcdctl` on the host**, so we exec into the etcd static pod
(the image ships `etcdctl`/`etcdutl`; the pod mounts the host's `/var/lib/etcd`, so files
written there are visible on cp1).

```bash
kubectl -n kube-system exec etcd-cp1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/etcd-backup.db

# verify
kubectl -n kube-system exec etcd-cp1 -- etcdutl snapshot status /var/lib/etcd/etcd-backup.db -w table
```
**Key points**: a snapshot is a point-in-time copy of the whole key space. On the real exam
`etcdctl` is usually on the control-plane node — the flags (`--endpoints`, `--cacert`,
`--cert`, `--key`) are the same; only the way you *invoke* it changes.

### T2 — Restore into a new data directory (verify the backup)
```bash
kubectl -n kube-system exec etcd-cp1 -- etcdutl \
  snapshot restore /var/lib/etcd/etcd-backup.db \
  --data-dir=/var/lib/etcd/restore

# check the restored member directory
sudo ls /var/lib/etcd/restore/member    # -> snap  wal
```
**Key points**: restoring into a **fresh** data-dir proves the snapshot is usable without
touching the live cluster. A *real* recovery would then stop the API server, point
`etcd.yaml`'s `--data-dir`/`hostPath` at the restored directory and restart — this is a
**destructive, one-shot** operation and is intentionally out of scope for auto-grading.

---

## 🔐 Certificates & CSR

### T3 — Approve the pending CSR
```bash
kubectl get csr applicant                 # CONDITION: Pending
kubectl certificate approve applicant
kubectl get csr applicant -o wide         # CONDITION: Approved,Issued

# Export the issued certificate (base64 PEM → decoded file)
kubectl get csr applicant -o jsonpath='{.status.certificate}' | base64 -d > /opt/cka/applicant.crt
```
**Key points**: a `CertificateSigningRequest` with signer `kubernetes.io/kube-apiserver-client`
is signed automatically **once approved** by the controller-manager. `.status.certificate`
then holds the issued cert (base64 PEM). ⚠️ Approved CSRs are **garbage-collected after ~1 h**
— export the certificate right away; the file is what the grader trusts long-term.

### T6 — Report the kube-apiserver certificate expiration
```bash
sudo kubeadm certs check-expiration | grep -E '^apiserver '
# e.g.  apiserver   Aug 28, 2027 09:48 UTC   364d   ca   no
echo "Aug 28, 2027" > /opt/cka/apiserver-expiration.txt   # copy the date shown for apiserver
```
**Key points**: `kubeadm certs check-expiration` lists every managed certificate and its
expiry. `kubeadm certs renew apiserver` would renew it (then restart the API server pod to
reload) — not required here.

---

## 👤 RBAC & Authorization

### T4 — Cluster-wide read-only for group `viewers`
```bash
kubectl create clusterrole pod-viewer --verb=get,list,watch --resource=pods
kubectl create clusterrolebinding pod-viewer-binding \
  --clusterrole=pod-viewer --group=viewers

# verify
kubectl auth can-i list   pods --all-namespaces --as=tester --as-group=viewers   # yes
kubectl auth can-i delete pods --all-namespaces --as=tester --as-group=viewers   # no
```
**Key points**: a `ClusterRole` + `ClusterRoleBinding` grants a permission across **all**
namespaces. `auth can-i --as/--as-group` is the way to test authorization without real users.

### T5 — Namespaced configmap management for user `auditor`
```bash
kubectl -n finance create role cm-manager \
  --verb=get,list,create,update --resource=configmaps
kubectl -n finance create rolebinding auditor-cm \
  --role=cm-manager --user=auditor

# verify
kubectl auth can-i create configmaps -n finance --as=auditor    # yes
kubectl auth can-i create configmaps -n default --as=auditor    # no
```
**Key points**: a `Role` + `RoleBinding` are **namespaced** — the grant applies only inside
`finance`. Using a `ClusterRoleBinding` here would wrongly grant it everywhere.

---

## 🖥️ Nodes & Static Pods

### T7 — Drain node w1 for maintenance
```bash
kubectl drain w1 --ignore-daemonsets --delete-emptydir-data
kubectl get node w1                       # STATUS: Ready,SchedulingDisabled
kubectl -n legacy get pods -o wide        # legacy-app pods no longer on w1
```
**Key points**: `drain` = `cordon` (mark unschedulable) **+** evict the workloads.
`--ignore-daemonsets` is needed because DaemonSet pods are not evicted; `--delete-emptydir-data`
allows evicting pods using `emptyDir`. After maintenance you would `kubectl uncordon w1`.

### T8 — Create a static pod on cp1
A static pod is managed by the **kubelet**, from `/etc/kubernetes/manifests/`, not the API.

```bash
sudo tee /etc/kubernetes/manifests/web-static.yaml >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-static
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    ports:
    - containerPort: 80
EOF
# the kubelet creates the mirror pod automatically
kubectl get pod web-static-cp1 -o wide    # Running; name gets the node suffix -cp1
```
**Key points**: the kubelet appends the node name to the pod (`web-static` → `web-static-cp1`)
and the mirror pod's `ownerReferences.kind` is **Node**. It is not subject to the scheduler,
so cp1's control-plane taint does not stop it. Delete it by removing the manifest file.

---

## 🧭 General method
1. `kubectl get nodes,csr` and `kubectl -n kube-system get pods` for the control-plane view.
2. etcd → always exec into `etcd-cp1`; snapshots live under the mounted `/var/lib/etcd`.
3. RBAC → build the object, then **prove** it with `auth can-i --as`.
4. Static pods → files in `/etc/kubernetes/manifests/` on the node, verified by the mirror pod.
