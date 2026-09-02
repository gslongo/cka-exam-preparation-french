# 🧪 CKA — Mock exam #4 · Targeted drills (killer.sh — session 2)

> Second **killer.sh-based** set (~1:1 mapping with a real session), complementary to
> [exam-03](../exam-03/EXAM.md). The tasks are **independent**: you can do just one at a time.
> **100 pts · pass ≥ 66 %.**

## Getting started
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-04/setup.sh"   # seed the starting state
# … you solve the tasks …
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-04/grade.sh"   # grade yourself (read-only)
```
> `setup.sh` is **idempotent**: it cleans up the previous answers before re-seeding.
> The solutions are in [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — open it only afterwards.

---

## 🌐 DNS & Service discovery

### T1 — Service & Pod DNS FQDNs (6 pts) · on `cp1`
The *Deployment* `controller` in *Namespace* **`q4-control`** communicates with various
cluster-internal endpoints using their DNS **FQDN** values, injected as environment
variables from a *ConfigMap*.

Update the ConfigMap **used by the Deployment** with the correct FQDN values for:

1. **`DNS_1`**: *Service* `kubernetes` in *Namespace* `default`
2. **`DNS_2`**: Headless *Service* `department` in *Namespace* `q4-workload`
3. **`DNS_3`**: *Pod* `section100` in *Namespace* `q4-workload` — it must keep working
   **even if the Pod IP changes**
4. **`DNS_4`**: a *Pod* with IP `1.2.3.4` in *Namespace* `kube-system`

Ensure the *Deployment* actually **runs with the updated values**.

> 💡 You can verify each name with `nslookup` from inside a `controller` Pod. Remember how
> env vars sourced from a ConfigMap behave when the ConfigMap changes.
> Expected: the 4 keys hold the correct FQDNs (a trailing dot is accepted) and the running
> Pods see the new values.

---

## 🏛️ Static Pods & Services

### T2 — Static Pod exposed by a NodePort (6 pts) · on `cp1`
Create a **static Pod** named **`my-static-pod`** in *Namespace* `default` on the
control-plane node (`cp1`). It must use image **`nginx:1-alpine`** and declare resource
**requests** of **`10m`** CPU and **`20Mi`** memory.

Then create a **NodePort** *Service* named **`static-pod-service`** which exposes that
static Pod on port **80**.

> ℹ️ For verification, check that the Service has **one Endpoint**. The Pod must also be
> reachable through the node's internal IP, e.g. `curl 192.168.56.10:NODE_PORT`.
> 💡 Give the static Pod **labels** — a Service only gets endpoints through its selector.
> Expected: mirror Pod `my-static-pod-cp1` Running with the requested resources; Service
> NodePort:80 with ≥ 1 endpoint, answering on the node IP.

---

## 🔐 Kubelet certificates

### T3 — Kubelet client & server certificate info (5 pts) · on `w1` + `cp1`
Node **`w1`** joined the cluster using `kubeadm` and **TLS bootstrapping**.

Find the **Issuer** and **Extended Key Usage** values on `w1` for:

1. the **kubelet client certificate** — used for **outgoing** connections to the
   kube-apiserver;
2. the **kubelet server certificate** — used for **incoming** connections from the
   kube-apiserver.

Write the information into **`/opt/exam-04/certificate-info.txt`** on `cp1`.

> ℹ️ Connect to the worker from the host with `vagrant ssh w1` (or from cp1:
> `ssh vagrant@192.168.56.11`, password `vagrant`).
> 💡 The kubelet keeps its certificates under `/var/lib/kubelet/pki/`.
> Expected: the file contains the two issuers and the two Extended Key Usage values.

---

## 🩺 Probes

### T4 — Readiness depending on another Service (7 pts) · on `cp1`
Do the following in *Namespace* `default`:

- Create a *Pod* named **`ready-if-service-ready`** (image **`nginx:1-alpine`**) with:
  - a **LivenessProbe** that simply executes the command **`true`**;
  - a **ReadinessProbe** that checks that **`http://service-am-i-ready:80`** is reachable
    (you can use `wget -T2 -O- http://service-am-i-ready:80`).
- Start the Pod and confirm it is **not Ready** because of the ReadinessProbe.

Then:

- Create a second *Pod* named **`am-i-ready`** (image **`nginx:1-alpine`**) with label
  **`id: cross-server-ready`**.
- The already existing *Service* **`service-am-i-ready`** should now have that second Pod
  as **endpoint**.
- The first Pod should now become **Ready** — check it.

> 💡 A Pod is only added to Service endpoints once **Ready** — here the first Pod's
> readiness literally depends on another Service having endpoints.
> Expected: probes configured as asked, `am-i-ready` endpoint behind the Service, and
> `ready-if-service-ready` Ready `1/1`.

---

## 📋 kubectl — sorting

### T5 — Sorted Pod listings (4 pts) · on `cp1`
Create two bash script files which use **`kubectl` sorting**:

1. **`/opt/exam-04/find_pods.sh`** — lists all *Pods* in **all Namespaces**, sorted by their
   AGE (`metadata.creationTimestamp`);
2. **`/opt/exam-04/find_pods_uid.sh`** — lists all *Pods* in **all Namespaces**, sorted by
   field `metadata.uid`.

> 💡 The scripts are **executed** by the grader — they must run as-is on cp1.
> Expected: each file contains a working `kubectl … --sort-by …` command over all namespaces.

---

## 🔧 Node troubleshooting

### T6 — Broken kubelet on the control plane (6 pts) · on `cp1`
There seems to be an issue with the **kubelet** on the control-plane node `cp1`:
**it's not running**.

Fix the kubelet and confirm that the node **`cp1`** is back in **Ready** state.

Then create a *Pod* called **`success`** in the `default` *Namespace*, image
**`nginx:1-alpine`**.

> ℹ️ Unlike the original single-node scenario, `cp1` keeps its control-plane taint here — the
> Pod may land on any node, that's fine.
> 💡 `systemctl status kubelet` · `journalctl -u kubelet` · `systemctl cat kubelet` — look at
> **every** drop-in the unit loads.
> Expected: kubelet `active (running)` on cp1, node `cp1` Ready, Pod `success` Running.

---

## 🗄️ etcd operations

### T7 — etcd version & snapshot (5 pts) · on `cp1`
Perform the following etcd operations:

1. Run **`etcd --version`** and store the output at **`/opt/exam-04/etcd-version`**.
2. Make a **snapshot** of etcd and save it at **`/opt/exam-04/etcd-snapshot.db`**.

> ℹ️ There is no `etcd`/`etcdctl` binary on the host: exec into the `etcd-cp1` Pod
> (`kubectl -n kube-system exec etcd-cp1 -- …`). The Pod mounts the host's `/var/lib/etcd`,
> so a snapshot written there appears on cp1 — move it to its final location afterwards.
> 💡 The server certificates live under `/etc/kubernetes/pki/etcd/` (also mounted in the Pod).
> Expected: the version file contains the real etcd version; the snapshot file is a **valid**
> etcd snapshot.

---

## 🏛️ Control plane components

### T8 — How is each component started? (5 pts) · on `cp1`
Check how the control-plane components **kubelet**, **kube-apiserver**, **kube-scheduler**,
**kube-controller-manager** and **etcd** are started/installed on the control-plane node.

Also find out the **name of the DNS application** and how it's started/installed in the
cluster.

Write your findings into **`/opt/exam-04/controlplane-components.txt`**, structured like:

```
kubelet: [TYPE]
kube-apiserver: [TYPE]
kube-scheduler: [TYPE]
kube-controller-manager: [TYPE]
etcd: [TYPE]
dns: [TYPE] [NAME]
```

Choices of `[TYPE]`: `not-installed`, `process`, `static-pod`, `pod`.

> 💡 Where does the kubelet read static-pod manifests? Which components have a systemd unit?
> Which ones run as regular Pods managed by a controller?

---

## 🧠 Scheduler

### T9 — Be the scheduler yourself (6 pts) · on `cp1`
**Temporarily** stop the **kube-scheduler** in a way that lets you start it again afterwards.

Create a single *Pod* named **`manual-schedule`** (image **`httpd:2-alpine`**) and confirm
it's created but **not scheduled** on any node.

Now *you* are the scheduler with all its power: **manually schedule** that Pod on node
**`cp1`**. Make sure it's **Running**.

Start the kube-scheduler again and confirm it works by creating a second *Pod* named
**`manual-schedule2`** (image **`httpd:2-alpine`**) and checking that it runs **on a worker
node** (`w1` or `w2`).

> 💡 How does the kubelet start the scheduler? Where would you « park » its definition?
> Note: manual scheduling bypasses the scheduler entirely — including its taint checks —
> which is why the Pod can land on the tainted `cp1`.
> Expected: scheduler healthy again, `manual-schedule` Running **on cp1**, `manual-schedule2`
> Running **on a worker**.

---

## 💾 Storage — dynamic provisioning

### T10 — StorageClass for a backup Job (7 pts) · on `cp1`
There is a backup *Job* which needs to be adjusted to use a *PVC* to store backups.

Create a *StorageClass* named **`local-backup`** which uses
**`provisioner: rancher.io/local-path`** and **`volumeBindingMode: WaitForFirstConsumer`**.
To prevent possible data loss, the StorageClass should **keep a PV retained** even if a bound
PVC is deleted.

Adjust the *Job* at **`/opt/exam-04/backup.yaml`** (Namespace **`q4-backup`**) to use a *PVC*
which requests **`50Mi`** storage and uses the new StorageClass.

The *PV* must be created **automatically by the provisioner**, not manually.

Deploy your changes, verify the Job **completed once** and the PVC is **Bound** to a newly
created PV.

> ℹ️ To re-run a Job, delete it and create it again. The `local-path` provisioner is installed
> in the cluster (namespace `local-path-storage`).
> Expected: SC with the 3 required fields; PVC 50Mi/local-backup Bound to an auto-provisioned
> PV; Job `backup` mounting that PVC and completed.

---

## 🔑 Secrets

### T11 — Secret as volume and as env (7 pts) · on `cp1`
Create *Namespace* **`q4-secret`** and implement the following in it:

- Create *Pod* **`secret-pod`** with image **`busybox:1`**. Keep it running with
  `sleep 1d` or similar.
- Create the existing *Secret* from **`/opt/exam-04/secret1.yaml`** and mount it
  **read-only** into the Pod at **`/tmp/secret1`**.
- Create a new *Secret* named **`secret2`** containing **`user=user1`** and **`pass=1234`**.
  These entries must be available inside the Pod's container as environment variables
  **`APP_USER`** and **`APP_PASS`**.

> 💡 Mount with `readOnly: true`; env vars via `valueFrom.secretKeyRef`.
> Expected: Pod Running; `/tmp/secret1` shows secret1's key; `APP_USER`/`APP_PASS` set in the
> container.

---

## 🎯 Scheduling — taints & tolerations

### T12 — Pod restricted to control-plane nodes (6 pts) · on `cp1`
Create a *Pod* of image **`httpd:2-alpine`** in *Namespace* `default`.

The Pod must be named **`pod1`** and its container **`pod1-container`**.

This Pod should **only** be scheduled on **control-plane** nodes.

Do **not** add new labels to any nodes, and do **not** use `nodeName`.

> 💡 Two things are needed: the *right* to land on a control-plane node, and the *constraint*
> to land only there. Look at cp1's existing taints and labels.
> Expected: `pod1` Running on `cp1`, with a control-plane toleration **and** a selector on an
> existing control-plane label.

---

## 🧭 Multi-container Pods

### T13 — Shared volume & Downward API (7 pts) · on `cp1`
Create a *Pod* with multiple containers named **`multi-container-playground`** in *Namespace*
`default`:

- It must have a **volume** attached and **mounted into each container**. The volume must
  **not** be persisted nor shared with other Pods.
- Container **`c1`** (image **`nginx:1-alpine`**) must expose the **name of the node** where
  the Pod runs as environment variable **`MY_NODE_NAME`**.
- Container **`c2`** (image **`busybox:1`**) must write the output of the `date` command
  **every second** into file **`date.log`** on the shared volume
  (e.g. `while true; do date >> /your/vol/path/date.log; sleep 1; done`).
- Container **`c3`** (image **`busybox:1`**) must constantly write the content of `date.log`
  from the shared volume to **stdout** (e.g. `tail -f /your/vol/path/date.log`).

> ℹ️ Check the logs of container `c3` to confirm the setup.
> 💡 « not persisted, not shared with other Pods » points at one precise volume type; the node
> name comes from the **Downward API** (`fieldRef`).
> Expected: Pod Running 3/3, `MY_NODE_NAME` correct in `c1`, dates flowing in `c3`'s logs.

---

## 🔎 Cluster introspection

### T14 — Cluster information file (5 pts) · on `cp1`
Find out the following information about the cluster:

1. How many **control-plane nodes** are available?
2. How many **worker nodes** (non control-plane) are available?
3. What is the **Service CIDR**?
4. Which **Networking (CNI) plugin** is configured, and **where is its config file**?
5. Which **suffix** will static pods have that run on `cp1`?

Write your answers into **`/opt/exam-04/cluster-info`**, structured like this:

```
# /opt/exam-04/cluster-info
1: [ANSWER]
2: [ANSWER]
3: [ANSWER]
4: [ANSWER]
5: [ANSWER]
```

> 💡 The Service CIDR is a **kube-apiserver flag**; the CNI config lives in the kubelet's
> standard CNI directory.

---

## 📰 Events & container runtime

### T15 — Watch what the kubelet repairs (6 pts) · on `cp1`
1. Write a `kubectl` command into **`/opt/exam-04/cluster_events.sh`** which shows the latest
   events **in the whole cluster**, ordered by time (`metadata.creationTimestamp`).
2. **Delete** the kube-proxy *Pod* running **on `cp1`** and write the events this caused into
   **`/opt/exam-04/pod_kill.log`**.
3. Manually **kill the containerd container** of the (new) kube-proxy Pod on `cp1` and write
   the events into **`/opt/exam-04/container_kill.log`**.

> 💡 `crictl ps` / `crictl rm -f` for the container part (root needed). Both kills are
> self-healing — watch *who* repairs each one.
> Expected: a working events script; both log files showing the kube-proxy events that each
> action produced.

---

## 🗂️ API resources & Namespaces

### T16 — Namespaced resources & crowded namespace (5 pts) · on `cp1`
Write the **names of all namespaced** Kubernetes resources (like *Pod*, *Secret*,
*ConfigMap*…) into **`/opt/exam-04/resources.txt`** — one name per line, as printed by
`-o name`.

Find the **`project-*`** *Namespace* with the **highest number of `Roles`** defined in it and
write **its name and the amount of Roles** into **`/opt/exam-04/crowded-namespace.txt`**.

> 💡 `kubectl api-resources` has a flag for the namespaced filter. Roles are namespaced —
> count them per `project-*` namespace.
> Expected: the full `-o name` list; the winning namespace with its Role count.

---

## 🧩 Kustomize & RBAC

### T17 — Operator permissions & new resource via Kustomize (7 pts) · on `cp1`
There is a Kustomize config available at **`/opt/exam-04/operator`**. It installs an operator
which works with different *CRDs*. It has been deployed like this:

```
kubectl kustomize /opt/exam-04/operator/prod | kubectl apply -f -
```

Perform the following changes **in the Kustomize base config**:

1. The operator needs to **`list`** certain *CRDs*. **Check its logs** to find out which ones
   and adjust the permissions of *Role* **`operator-role`**.
2. Add a new **Student** resource called **`student4`**, with any name and description.

Deploy your Kustomize config changes to **prod**.

> 💡 `kubectl -n q4-operator logs deploy/operator` — the operator retries every 20 s, so RBAC
> fixes show up in the logs without restarting anything.
> Expected: the Role covers every CRD the operator lists, the logs are error-free, and
> `student4` exists both in the cluster and in the rendered Kustomize output.

---

**Good luck!** Solutions: [solutions/SOLUTIONS.md](solutions/SOLUTIONS.md) — only after grading yourself.
