# 🧪 CKA — Mock exam #3 · Targeted drills (gaps)

> Complementary set: it **fills the CKA topics not covered** by exams #1 and #2
> (kubeconfig, etcd *restore*, CSR/user kubeconfig, HPA, DaemonSet, broken kubelet, `crictl`, etc.).
> The tasks are **independent**: you can do just one at a time.
> Provisional scoring — the set will be balanced over time.

## Getting started
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/setup.sh"   # seed the starting state
# … you solve the tasks …
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/grade.sh"   # grade yourself (read-only)
```
> `setup.sh` is **idempotent**: it cleans up the previous answers before re-seeding.
> The solutions are in [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — open it only afterwards.

---

## 🏛️ Cluster Architecture & kubeconfig

### T1 — Extract information from a kubeconfig (7 pts) · on `cp1`
A kubeconfig file **outside the cluster** is provided: `/opt/exam-03/kubeconfig`.
Without merging it into your current config, extract three pieces of information from it:

1. Write **all context names** (one per line) to `/opt/exam-03/contexts`.
2. Write the **current context name** to `/opt/exam-03/current-context`.
3. Write the **client-certificate** of user **`audit-user`**, **decoded from base64**, to `/opt/exam-03/cert`.

> 💡 Everything is done with `kubectl config … --kubeconfig=/opt/exam-03/kubeconfig` (+ `base64 -d` for the certificate). Do not modify the provided kubeconfig.
> Expected: the 3 files present and correct (the order of contexts does not matter).

---

## 📦 Packaging & Helm

### T2 — Install cert-manager with Helm + ClusterIssuer (8 pts) · on `cp1`
Install **cert-manager** via Helm, then create a `ClusterIssuer`.

1. Create the *Namespace* `pki`.
2. Install the `jetstack/cert-manager` chart (with `crds.enabled=true`) in that namespace. The Helm *release* must be named **`certman`**.
3. Edit the `ClusterIssuer` provided in `/opt/exam-03/issuer.yaml` to add `crlDistributionPoints: ["http://pki.cka.local/crl"]` under `spec.selfSigned`.
4. Create the `ClusterIssuer` from `/opt/exam-03/issuer.yaml`.

> ℹ️ cert-manager does not need to issue real certificates: installing the chart + creating the `ClusterIssuer` is enough.
> ⚠️ Wait until the cert-manager pods are **Ready** before creating the `ClusterIssuer`, otherwise the admission webhook rejects the creation.
> Expected: Helm release `certman` in `pki`, cert-manager CRDs present, `ClusterIssuer selfsigned-issuer` created with `crlDistributionPoints`.

---

## 🧱 Workloads & Scheduling

### T3 — Scale a StatefulSet (5 pts) · on `cp1`
In the *Namespace* `project-store`, several *Pods* `store-db-*` are running (a StatefulSet with 3 replicas).
To save resources, scale this StatefulSet down to **a single replica**.

> 💡 The `store-db-*` Pods belong to a StatefulSet: find the controller, then change its replica count (do not delete the Pods by hand — they would be recreated).
> Expected: the StatefulSet `store-db` has `replicas: 1` and 1 ready Pod.

### T4 — Identify the Pods evicted first (QoS) (6 pts) · on `cp1`
In the *Namespace* `project-qos`, inspect all *Pods* and find those that would be **evicted first** if a node runs out of resources (CPU or memory).
Write their names (**one per line**) to `/opt/exam-03/qos-evicted-first.txt`.

> 💡 Under resource pressure (node-pressure eviction), the order follows the **QoS class**: `BestEffort` first, then `Burstable`, and `Guaranteed` last.
> Expected: the file contains exactly the Pods of the most fragile QoS class (the order of lines does not matter).

---

## 🧩 HPA & Kustomize

### T5 — HPA via Kustomize (12 pts) · on `cp1`
The `api-gw` application has been deployed in the *Namespaces* `api-gw-staging` and `api-gw-prod` via Kustomize:

```bash
kubectl kustomize /opt/exam-03/kustomize/api-gw/overlays/staging | kubectl apply -f -
kubectl kustomize /opt/exam-03/kustomize/api-gw/overlays/prod    | kubectl apply -f -
```

Starting from the Kustomize config in `/opt/exam-03/kustomize/api-gw`, do the following:

1. Completely remove the *ConfigMap* `scaling-config`.
2. Add an *HPA* named `api-gw` for the *Deployment* `api-gw`, with min `2` and max `4` replicas, targeting **50%** average CPU utilization.
3. In **prod**, the HPA must have max `6` replicas.
4. Apply your changes for staging **and** prod (reflected in the cluster).

> 💡 metrics-server is not required: only the HPA object (min/max/target) is evaluated (the target will show `<unknown>`, that's normal).
> ⚠️ `kubectl apply` does not **prune** resources removed from the kustomize — remember to delete the ConfigMap already present in the cluster.
> Expected: HPA `api-gw` in both ns (staging max 4, prod max 6, target 50%), and `ConfigMap scaling-config` absent from both ns.

---

## 💾 Storage

### T6 — PV + PVC (without StorageClass) mounted by a Deployment (10 pts) · on `cp1`
1. Create a *PersistentVolume* `data-pv`: capacity **1Gi**, accessMode **ReadWriteOnce**, hostPath `/mnt/data-vol`, **without** `storageClassName`.
2. Create a *PersistentVolumeClaim* `data-pvc` in the *Namespace* `storage-app`: request **1Gi**, accessMode **ReadWriteOnce**, **without** `storageClassName`. It must be **Bound** to the PV.
3. Create a *Deployment* `webstore` in `storage-app`, image `httpd:2-alpine`, that mounts this volume at `/var/www/data`.

> 💡 "without storageClassName" = do not set this field at all (neither on the PV nor on the PVC). A PVC without SC binds to a PV without SC.
> Expected: PV `data-pv` **Bound**, PVC `data-pvc` **Bound** to the PV, Deployment `webstore` (httpd:2-alpine) mounting the PVC at `/var/www/data`.

---

## 📊 Observability

### T7 — `kubectl top` scripts (metrics-server) (10 pts) · on `cp1`
The *metrics-server* is installed in the cluster. Write two bash scripts using `kubectl`:

1. `/opt/exam-03/node.sh`: display the resource usage of the **nodes**.
2. `/opt/exam-03/pod.sh`: display the resource usage of the **Pods and their containers**.

> 💡 It's `kubectl top`. To detail each container of a Pod: the `--containers` option.
> Expected: `node.sh` invokes `kubectl top nodes` (and returns metrics); `pod.sh` invokes `kubectl top pod --containers`.

---

## 🔧 Node lifecycle (kubeadm)

### T8 — Join a worker + upgrade node (10 pts) · on `cp1`
A new *worker* node must join the cluster, and an existing worker on an older version must be upgraded. **Without modifying the cluster or touching the nodes**, prepare the following two artifacts on `cp1`:

1. From the *control plane*, generate a **complete join command** (with a **real** `token` and the CA *hash*) and save it as-is to `/opt/exam-03/join-command.txt`.
2. In `/opt/exam-03/upgrade-node.sh`, write the **worker upgrade runbook**: the commands to run *on the worker* to align it with the control plane version (upgrade of the `kubelet` package, `kubeadm upgrade node`, kubelet restart).

> 💡 The join command is generated in one shot with `kubeadm token create --print-join-command`. On the worker side, you **do not use** `kubeadm upgrade apply` (reserved for the control plane) but `kubeadm upgrade node`.
> ⚠️ **Non-destructive** task: you neither actually join nor upgrade a node here — you produce the artifacts. (killer.sh, on the other hand, does it for real on its environment.)
> Expected: `join-command.txt` contains a `kubeadm join …:6443 --token … --discovery-token-ca-cert-hash sha256:…` with an existing token; `upgrade-node.sh` contains `kubeadm upgrade node` + kubelet update/restart.

---

## 🔐 Kubernetes API from a Pod

### T9 — Query the API from a Pod via ServiceAccount (10 pts) · on `cp1`
In the *Namespace* `project-audit`, the *ServiceAccount* `probe-sa` is allowed to list the namespace's *Secrets*.

1. Create a *Pod* named `secret-probe`, image `nginx:1-alpine`, that **uses the ServiceAccount `probe-sa`**.
2. Enter the Pod (`kubectl exec`) and, with `curl`, **manually** query the Kubernetes API to list **all Secrets** in the `project-audit` namespace (authenticating with the ServiceAccount token mounted in the Pod).
3. Write the API's JSON response to `/opt/exam-03/secrets.json`.

> 💡 In the Pod, the token and the CA are mounted under `/var/run/secrets/kubernetes.io/serviceaccount/`; the internal API is reachable at `https://kubernetes.default.svc`. `curl` authenticates with the `Authorization: Bearer <token>` header and `--cacert ca.crt`. (`nginx:1-alpine` does not have `curl` → `apk add --no-cache curl` in the Pod.)
> Expected: Pod `secret-probe` (`nginx:1-alpine`) using `probe-sa`, and `secrets.json` = API `SecretList` response containing the Secret `audit-key`.

---

## 🛰️ DaemonSet & scheduling

### T10 — DaemonSet on all nodes, including the control-plane (10 pts) · on `cp1`
In the *Namespace* `project-batch`, create a *DaemonSet* named `log-harvester`:

1. Image `httpd:2-alpine`, with the labels `id=log-harvester` and `uuid=7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64`.
2. Each *Pod* requests **15 millicores** of CPU and **20 Mi** of memory (`requests`).
3. The *Pods* must run on **all nodes**, **including the control-plane** (`cp1`).

> 💡 By default the control-plane carries a *taint* `node-role.kubernetes.io/control-plane:NoSchedule`: to schedule a Pod there, add the matching *toleration* in the DaemonSet template.
> Expected: DaemonSet `log-harvester` scheduled and **Ready on all 3 nodes** (labels + requests compliant).

### T11 — Multi-container Deployment + anti-affinity (10 pts) · on `cp1`
In the *Namespace* `project-batch`, create a *Deployment* named `edge-cache`:

1. **3 replicas**, with the label `id=edge-node` on the *Deployment* **and** its *Pods*.
2. Two containers: `main` (image `nginx:1-alpine`) and `sidecar` (image `registry.k8s.io/pause:3.10`).
3. There must be **only one** *Pod* of this *Deployment* **per node** — use a **Pod anti-affinity** with `topologyKey: kubernetes.io/hostname`.

> ℹ️ Since there are only **2 schedulable worker nodes** (the control-plane is *tainted*) and **3 replicas**, the **3rd Pod will stay `Pending`** — that's the expected behavior (like a simulated DaemonSet).
> Expected: Deployment `edge-cache` (3 replicas, label `id=edge-node`, containers `main`+`sidecar`), anti-affinity `kubernetes.io/hostname`, **2 Pods `Running` + 1 `Pending`**.

---

## 🔐 Cluster certificates

### T13 — kubeadm certificate expiry & renewal (10 pts) · on `cp1`
Inspect the control plane certificates:

1. Check **how long the `kube-apiserver` server certificate is valid** (with `openssl` on `/etc/kubernetes/pki/apiserver.crt`) and write its **expiration date** to `/opt/exam-03/apiserver-expiration`. Confirm with `kubeadm certs check-expiration` that both methods give the same date.
2. In `/opt/exam-03/renew-apiserver.sh`, write the **`kubeadm` command** that **would renew** the `kube-apiserver` certificate (do not run it).

> 💡 `openssl x509 -noout -enddate -in …` gives the `notAfter`; `kubeadm certs check-expiration` lists all the dates. A targeted renewal is done with `kubeadm certs renew <component>`.
> Expected: `apiserver-expiration` contains the apiserver cert's expiration date/year; `renew-apiserver.sh` contains `kubeadm certs renew apiserver`.

---

## 🛡️ Networking — NetworkPolicy egress

### T14 — Restrict a backend's egress (10 pts) · on `cp1`
Following an incident, a compromised `backend-*` *Pod* was able to reach the entire cluster. In the *Namespace* `project-mesh`, create a *NetworkPolicy* named `np-egress` that allows `backend-*` *Pods* to **only**:

- connect to `cache-a-*` *Pods* on port `6379`;
- connect to `cache-b-*` *Pods* on port `5432`.

Any other egress (e.g. to `vault-*` on `9999`) must be **blocked**. Use the *Pods'* `app` labels in your policy.

> 💡 It's an **egress** policy (`policyTypes: [Egress]`): `podSelector` selects `app=backend`, and each `egress` rule pairs a `to.podSelector` (`app=cache-a` / `app=cache-b`) with its `ports`. Put **one rule per target** (otherwise you allow the cross-product of ports).
> Expected: `np-egress` selects `app=backend`, type `Egress`, allows `app=cache-a:6379` and `app=cache-b:5432` (and nothing else).

---

## 🔎 Debug — container runtime (`crictl`)

### T16 — Inspect a container with `crictl` (10 pts) · on `cp1`
A *Pod* `probe-httpd` (image `httpd:2-alpine`) is running in the *Namespace* `project-batch`, on node `cp1`. `kubectl` is not enough: you must go through the **runtime** to audit it. Using `crictl` on `cp1`:

1. Find this *Pod's* **container ID** and its **runtime type** (the `info.runtimeType` field of `crictl inspect`), then write both to `/opt/exam-03/container-info.txt`.
2. Retrieve the container's **logs** and write them to `/opt/exam-03/container.log`.

> 💡 `sudo crictl ps` lists the containers (`NAME`/`POD` columns); `sudo crictl inspect <id>` gives the JSON detail (including `.info.runtimeType`, often `io.containerd.runc.v2`); `sudo crictl logs <id>` outputs the logs. Filter with `--name probe-httpd` or `grep`.
> Expected: `container-info.txt` contains a container ID (hexadecimal) **and** the runtime type (`runc`); `container.log` exists.

---

## 🚪 Gateway API — HTTP routing

### T12 — Route traffic with an HTTPRoute (10 pts) · on `cp1`
The cluster already exposes a *Gateway* `edge-gw` (class `eg-class`) in the *Namespace* `project-edge`. We are replacing an old *Ingress* with the **Gateway** API. Create an *HTTPRoute* named `route-splitter` in `project-edge`, attached to the *Gateway* `edge-gw`, that:

- routes the path prefix `/web` to the *Service* `web-svc:80`;
- routes the path prefix `/svc` to the *Service* `api-svc:80`;
- for the `/shop` prefix: route to `premium-svc:80` **only if** the request carries the **`X-Tier: premium`** header (path **AND** header in the **same** *match*), and to `standard-svc:80` **otherwise** (catch-all `/shop`).

> 💡 API `gateway.networking.k8s.io/v1`, `kind: HTTPRoute`. Attachment via `spec.parentRefs` (the *Gateway* name). A `match` that lists both `path` **and** `headers` applies a **logical AND** (both must match); splitting them into two `matches` would give an **OR**. Place the `/shop` + header rule **before** the `/shop` catch-all: the **order of rules matters** (the first match wins). The *Services* do not need to exist to validate the object.
> Expected: `route-splitter` references `edge-gw`; routes `/web` and `/svc` by prefix; `/shop` + `X-Tier: premium` → premium; `/shop` alone → standard.

---

## 🧭 CoreDNS — custom domain

### T15 — Add a domain to CoreDNS (10 pts) · on `cp1`
CoreDNS resolves internal DNS via the *ConfigMap* `coredns` (*Namespace* `kube-system`). We want names of the form `SERVICE.NAMESPACE.svc.cka.local` to resolve **exactly** like their `…svc.cluster.local` equivalents.

1. **First back up** the full `coredns` *ConfigMap* to `/opt/exam-03/coredns_original.yaml`.
2. Modify the **Corefile** so that the `cka.local` domain is served by the `kubernetes` plugin (just like `cluster.local`).

> 💡 `kubectl -n kube-system get cm coredns -o yaml` for the backup; `kubectl -n kube-system edit cm coredns` to edit. On the `kubernetes` plugin line, add the zone: `kubernetes cluster.local cka.local in-addr.arpa ip6.arpa { … }`. Reload with `kubectl -n kube-system rollout restart deployment coredns` (or wait for the `reload` plugin).
> Expected: `coredns_original.yaml` is the backup of the `coredns` *ConfigMap*; the active Corefile declares `cka.local` on the `kubernetes` plugin line.

---

## 🗄️ etcd — introspection

### T17 — etcd information (9 pts) · on `cp1`
etcd runs as a *static Pod* on `cp1`. **Without modifying anything**, find the following information and write it to `/opt/exam-03/etcd-info.txt`:

- the location of etcd's **server private key**;
- the **expiration date** of etcd's **server certificate**;
- whether **client certificate authentication** is enabled (yes/no).

> 💡 The `/etc/kubernetes/manifests/etcd.yaml` manifest lists etcd's flags (`--key-file`, `--cert-file`, `--client-cert-auth`). `openssl x509 -noout -enddate -in <cert>` gives the expiration date. The file's free-form format does not matter, as long as the three pieces of information are present.
> Expected: `etcd-info.txt` contains the path of `server.key`, the server cert's expiration year, and the state of `client-cert-auth`.

---

## 🔀 kube-proxy — iptables mode

### T18 — A Service's iptables rules (8 pts) · on `cp1`
The cluster uses **kube-proxy in iptables mode**. In the `project-proxy` namespace (already created):

- create a Pod `p-proxy` from the `nginx:1-alpine` image;
- expose it with a **ClusterIP** Service named `proxy-svc` on port **3100**, forwarded to the container's port **80**;
- write to `/opt/exam-03/iptables.txt` the **iptables rules** (`nat` table) generated by kube-proxy for this Service.

> 💡 `sudo iptables-save -t nat | grep proxy-svc` (or `grep <clusterIP>`). The `KUBE-SERVICES` → `KUBE-SVC-*` chains carry traffic to the Service. **Keep the Service in place** for grading.
> Expected: Pod `p-proxy` running, Service `proxy-svc` (3100→80), `iptables.txt` contains the Service's `KUBE-SVC` rules.

---

## 🌐 Service CIDR — extend the Services IP range

### T19 — Add a Services IP range (10 pts) · on `cp1`
**Without restarting the kube-apiserver**, you will add a new Services IP range to the cluster thanks to the **ServiceCIDR** API (GA). In the `project-range` namespace (already created):

- create a Pod `range-probe` from the `httpd:2-alpine` image;
- expose it with a first **ClusterIP** Service `range-svc` on port **80** (it gets an IP from the default range);
- create a **ServiceCIDR** object named `extra-range` covering the range **`11.96.0.0/12`**;
- create a second **ClusterIP** Service `range-svc2` to the **same** Pod (port 80), assigning it a **clusterIP belonging to `11.96.0.0/12`**.

> 💡 `kubectl get servicecidr` shows the default range (`kubernetes`), which is **immutable**: a prompt saying to "change" the range in practice means **adding** a ServiceCIDR (the `--service-cluster-ip-range` flag is not touched). For `range-svc2`, set `spec.clusterIP` within `11.96.0.0/12` (e.g. `11.96.0.10`).
> Expected: ServiceCIDR `extra-range` (`11.96.0.0/12`) present; `range-svc2` has a clusterIP within `11.96.0.0/12`.
