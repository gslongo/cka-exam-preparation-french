# 🧪 Lab setup — Local kubeadm cluster (K8s 1.34 → upgrade 1.35)

> Automatic provisioning of a **1 CP + 2 workers** cluster on your host machine via Vagrant/VirtualBox. Reproduces the CKA exam environment (kubeadm, containerd, Calico), impossible to test on EKS.

> 🇬🇧 **Language**: everything under `lab-setup/` — this doc, the **labs** ([labs/](labs/)) and **mock exams** ([mock-exam/](mock-exam/)) with their statements, solutions and graders — is **intentionally in English** (CKA style, to get used to exam-day wording); the revision sheets at the repo root remain in French.

> 📖 **Train like the real exam**: while solving the labs, restrict yourself to the **official docs** (<https://kubernetes.io/docs/>) plus **`kubectl explain`** / `--help` — the only help allowed on exam day. Getting fast at *finding* answers there is a skill to train, not an obstacle.

---

## Host machine prerequisites

| Component | Min version | Notes |
|---|---|---|
| **CPU** | 6 spare vCPUs | 2 per VM × 3 VMs |
| **RAM** | 6 GB free | 2 GB per VM × 3 VMs |
| **Disk** | 20 GB free | ~7 GB / VM |
| **Vagrant** | 2.4+ | `brew install --cask vagrant` / `apt install vagrant` |
| **VirtualBox** | 7.0+ | Alternative: libvirt (adapt the `Vagrantfile`) |

## ⚠️ Known pitfalls

- **`vagrant up` without `--no-parallel`**: the workers try to join before cp1 has generated the token → failure. Use `--no-parallel` the first time.
- **VirtualBox host-only network**: on recent macOS, you must allow VirtualBox in System Settings > Privacy & Security after the first install.
- **Swap**: disabled automatically by the script (K8s 1.34+ supports swap but off = simpler).
- **Ubuntu box GPG issue**: if `apt-get update` fails on a key, `vagrant reload --provision` usually fixes it.
- **After `vagrant snapshot restore`**: nodes can be transiently `NotReady` and the Calico CNI token may have expired — the `setup.sh` health gate ([check-cluster-health.sh](check-cluster-health.sh)) waits and auto-repairs both.

## What gets installed

| Component | Version | Role |
|---|---|---|
| **Ubuntu** | 22.04 LTS (bento box) | OS |
| **containerd** | Ubuntu apt (~1.7) | CRI container runtime |
| **Kubernetes** | 1.34.x | kubeadm + kubelet + kubectl — **init at 1.34** to practise the upgrade → 1.35 (CKA exam version) |
| **Calico** | v3.28.1 (via tigera-operator) | CNI + NetworkPolicy (**not available on EKS/VPC CNI by default**) |
| **Pod CIDR** | `10.244.0.0/16` | — |
| **Service CIDR** | `10.96.0.0/12` (default) | — |

## Network

| VM | Private IP | Role |
|---|---|---|
| `cp1` | `192.168.56.10` | control plane |
| `w1` | `192.168.56.11` | worker |
| `w2` | `192.168.56.12` | worker |

## Usage

```bash
cd lab-setup/

# 1. Bring the cluster up (~10-15 min the first time: box download + install)
vagrant up --no-parallel        # sequential so cp1 generates the token before the workers

# 2. SSH into the control plane
vagrant ssh cp1

# --- inside the cp1 VM ---
kubectl get nodes
# NAME   STATUS   ROLES           AGE   VERSION
# cp1    Ready    control-plane   5m    v1.34.x   ← init at 1.34 (upgrade to 1.35 to practise)
# w1     Ready    <none>          3m    v1.34.x
# w2     Ready    <none>          3m    v1.34.x

kubectl get pods -A          # everything Running (calico, coredns, kube-*)
```

## Useful commands

```bash
vagrant status                 # state of the 3 VMs
vagrant halt                   # clean stop
vagrant up                     # restart (no reprovisioning)
vagrant reload --provision     # reboot + re-run scripts
vagrant destroy -f             # delete everything
vagrant ssh w1                 # SSH into a worker
```

## Snapshot / restore (fastest way to reset the cluster)

```bash
# Right after the first successful `vagrant up` (healthy baseline cluster)
vagrant snapshot save clean

# Any time you want a fresh cluster (after breaking things, finishing a lab…)
vagrant snapshot restore clean
```

> 💡 **Recommended**: save the `clean` snapshot as soon as the cluster is up — a restore takes
> ~1 min versus ~10 min for a full `destroy`/`up`. After a restore, nodes can stay `NotReady` for a
> short while and the Calico CNI token may have expired: every lab/exam `setup.sh` runs a **health
> gate** ([check-cluster-health.sh](check-cluster-health.sh)) that waits for the nodes and
> auto-repairs Calico — just run the `setup.sh` of your lab and let it settle.

## Rebuilding the cluster from scratch

```bash
vagrant destroy -f
vagrant up --no-parallel
```

Allow ~10 min. The Ubuntu box is cached after the first download.

## 🧪 Themed labs

The [labs/](labs/) folder contains **focused labs** on one topic each (unlike the mock exams, which sweep the whole curriculum). Each keeps the same **self-graded** mechanics (`LAB.md` + `setup.sh` + `grade.sh` + `solutions/`) but with no time limit.

- [labs/lab-services-ingress-gateway/](labs/lab-services-ingress-gateway/) — **Services · Ingress · Gateway API** (100 pts, target 75 %). Services tested live (connectivity); Ingress/Gateway graded on the object (no controller installed). Installs the Gateway API CRDs if needed.
- [labs/lab-storage-config-multicontainer/](labs/lab-storage-config-multicontainer/) — **Storage · ConfigMap/Secrets · Sidecars** (100 pts, target 75 %). Static PV/PVC binding and Pods tested live; StorageClass graded on the object (no CSI provisioner). Includes recovering a `Released` PV (claimRef) and the native sidecar (K8s 1.29+).
- [labs/lab-troubleshooting/](labs/lab-troubleshooting/) — **🔧 Cross-cutting Troubleshooting** (100 pts, target 75 %). **Everything is broken at the start**, to diagnose and fix: 16 breakages across the 4 domains (RBAC, static pod on `cp1`, node `w1` out of service, finalizer, `ImagePull`/`CrashLoop`/config, `Pending`, readiness, selector/`targetPort`/NetworkPolicy/DNS, PVC). Everything is fixable from `cp1` + `kubectl` and tested live.
- [labs/lab-cluster-maintenance/](labs/lab-cluster-maintenance/) — **🛠️ Cluster Maintenance, etcd & Security** — domain 01 (100 pts, target 75 %). An **operational** lab: you run real admin operations (etcd backup/restore via `exec` in the `etcd-cp1` pod, CSR approval, ClusterRole/Role RBAC, `drain` of `w1`, static pod on `cp1`). Everything is driven from `cp1`.
- [labs/lab-workloads-scheduling/](labs/lab-workloads-scheduling/) — **📦 Workloads & Scheduling** — domain 02 (100 pts, target 75 %). A **build** lab: you author 12 objects (Deployment + scale, `RollingUpdate`, DaemonSet, Job/CronJob, HPA, QoS, `nodeSelector`, `nodeAffinity`, taint+toleration, `topologySpreadConstraints`, `PriorityClass`). Placement verified on `w1`/`w2`.

```bash
# Prepare / grade yourself (same principle as the exams)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"

# Storage · ConfigMap/Secrets · Sidecars lab
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"

# Cross-cutting Troubleshooting lab (everything is broken, fix it)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/grade.sh"

# Cluster Maintenance, etcd & Security lab (domain 01)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-cluster-maintenance/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-cluster-maintenance/grade.sh"

# Workloads & Scheduling lab (domain 02)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-workloads-scheduling/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-workloads-scheduling/grade.sh"
```

## 📝 CKA mock exams

The [mock-exam/](mock-exam/) folder contains the **self-graded** mock exams, one subfolder per paper: [exam-01/](mock-exam/exam-01/) (intermediate), [exam-02/](mock-exam/exam-02/) (**advanced**) — 16 tasks, 100 pts, 66 % threshold, ~2 h each — and [exam-03/](mock-exam/exam-03/) (**expert — killer.sh-style drills**). Overview, weighting and file list: see the [main README](../README.md). Below, the **how-to** on the lab (replace `exam-01` with the paper of your choice):

```bash
# 1. Prepare the environment (on cp1, via the synced /vagrant folder)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"

# 2. Sit the ~2 h paper on the cluster following mock-exam/exam-01/EXAM.md
#    (most tasks on cp1; the "static pod" task is done on w1)

# 3. Grade yourself
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/grade.sh"

# 4. Start over (re-seeds the starting state)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"
```

> 💡 `setup.sh` (run on cp1) cleans the exam namespaces, the PV, `w1`'s label, uncordons the workers and removes the etcd snapshot. The **static pod** lives on `w1`'s disk: to start truly clean, remove it by hand → `vagrant ssh w1 -c "sudo rm -f /etc/kubernetes/manifests/static-web.yaml"`.
> No `vagrant destroy` is needed for these exams (everything happens at the K8s object level); for **exam-02**, `setup.sh` additionally removes `w1`'s taint and the created ClusterRole/Binding.

