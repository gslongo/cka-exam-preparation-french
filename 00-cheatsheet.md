# 00 — Cheatsheet CKA

> Condensé imprimable (A4). À réviser J-7 puis J-1. **Anglais conservé** pour les termes techniques.

## ⚡ Setup initial (à taper en 30 s à l'exam)

```bash
alias k=kubectl
export do='--dry-run=client -o yaml'   # génère un manifest
export now='--force --grace-period=0'  # delete immédiat
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# Contexte par défaut
kubectl config set-context --current --namespace=<ns>
```

## 🔑 kubeconfig post-init (à copier de l'output kubeadm)

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# ou, en root : export KUBECONFIG=/etc/kubernetes/admin.conf
```

## 🧭 Commande → effet (référence)

| Commande | Effet |
|---|---|
| `k run p --image=nginx $do > p.yaml` | Génère manifest Pod |
| `k create deploy web --image=nginx --replicas=3 $do` | Génère manifest Deployment |
| `k expose deploy web --port=80 --target-port=8080` | Crée un `ClusterIP` Service |
| `k scale deploy web --replicas=5` | Scale |
| `k rollout status deploy/web` | Suit un rollout |
| `k rollout undo deploy/web` | Rollback |
| `k set image deploy/web c=nginx:1.25` | Change image |
| `k label node n1 disk=ssd` | Ajoute label |
| `k taint node n1 key=val:NoSchedule` | Ajoute taint |
| `k drain n1 --ignore-daemonsets --delete-emptydir-data` | Vide un node |
| `k cordon n1` / `k uncordon n1` | Verrouille/déverrouille scheduling |
| `k top pod -A` | Consommation (metrics-server) |
| `k auth can-i <verb> <res> --as=<user>` | Test RBAC |
| `k get ev --sort-by=.lastTimestamp` | Events triés |
| `k debug node/n1 -it --image=busybox` | Ephemeral debug node |
| `k debug pod/p -it --image=busybox --target=c` | Ephemeral debug container |

## 🧯 Problème → 1re commande à taper
| Symptôme | Réflexe |
|---|---|
| Pod `Pending` | `k describe pod` → events (scheduling, PVC, image) |
| Pod `ImagePullBackOff` | `k describe` → registry, secret `imagePullSecret` |
| Pod `CrashLoopBackOff` | `k logs -p` (previous) + `k describe` |
| Pod `Init:...` | `k logs <pod> -c <initContainer>` |
| Service ne répond pas | `k get ep <svc>` → endpoints vides = selector KO |
| DNS KO | `k -n kube-system get pod -l k8s-app=kube-dns` |
| Node `NotReady` | `ssh <node>` → `systemctl status kubelet` + `journalctl -u kubelet -e` |
| `kubectl` inaccessible / apiserver down | Descendre au runtime : `sudo crictl ps -a` + `crictl logs` (voir bloc ci-dessous) |
| PVC `Pending` | `k describe pvc` → StorageClass, capacity, accessModes |
| Certificat expiré | `kubeadm certs check-expiration` → `kubeadm certs renew all` |
| Ajouter un worker / token expiré (>24 h) | Sur le CP : `kubeadm token create --print-join-command` |

### 🚑 crictl — debug quand `kubectl` ne répond plus
> L'apiserver est un **static Pod** : s'il crashe, `kubectl` est KO. `crictl` parle direct à containerd (ce que voit le kubelet). **Toujours `sudo`.**
```bash
sudo crictl ps -a | grep apiserver     # trouver le conteneur (même arrêté/crashé)
sudo crictl logs <container-id>         # LIRE l'erreur (flag/cert/port erroné)
sudo crictl inspect <container-id>      # détails complets si besoin
# → corriger /etc/kubernetes/manifests/kube-apiserver.yaml ; kubelet recrée le Pod (~30 s)
```
- `crictl ps` = conteneurs actifs · `ps -a` = + arrêtés · `crictl pods` = sandboxes
- Endpoint déjà réglé via `/etc/crictl.yaml` (sinon `--runtime-endpoint unix:///run/containerd/containerd.sock`)

## 📄 YAML minimaux

```yaml
# Pod
apiVersion: v1
kind: Pod
metadata: { name: p, labels: { app: web } }
spec:
  containers:
  - { name: c, image: nginx:1.25, ports: [{ containerPort: 80 }] }
```

```yaml
# Deployment + Service
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 3
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - { name: c, image: nginx:1.25, ports: [{ containerPort: 80 }] }
---
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
```

```yaml
# PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: standard
```

```yaml
# NetworkPolicy — deny-all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all }
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

## 🧩 apiVersion par kind (référence rapide)

| kind | apiVersion |
|---|---|
| Pod, Service, ConfigMap, Secret, Namespace, PersistentVolume(Claim), ServiceAccount, Node, Endpoints | `v1` (group **core**) |
| Deployment, ReplicaSet, StatefulSet, DaemonSet | `apps/v1` |
| Job, CronJob | `batch/v1` |
| Ingress, NetworkPolicy, IngressClass | `networking.k8s.io/v1` |
| Role, RoleBinding, ClusterRole, ClusterRoleBinding | `rbac.authorization.k8s.io/v1` |
| HorizontalPodAutoscaler | `autoscaling/v2` |
| PriorityClass | `scheduling.k8s.io/v1` |
| StorageClass, VolumeAttachment, CSIDriver | `storage.k8s.io/v1` |
| EndpointSlice | `discovery.k8s.io/v1` |
| PodDisruptionBudget | `policy/v1` |
| CustomResourceDefinition | `apiextensions.k8s.io/v1` |

> En cas de doute : `kubectl explain <kind>` (1re ligne = `VERSION`) ou `kubectl api-resources | grep -i <kind>`.

## 🔐 etcd — backup & restore (procédure figée)

```bash
# Variables (adapter chemins)
export ETCDCTL_API=3
CERT=/etc/kubernetes/pki/etcd
EP=https://127.0.0.1:2379

# Backup
etcdctl --endpoints=$EP \
  --cacert=$CERT/ca.crt --cert=$CERT/server.crt --key=$CERT/server.key \
  snapshot save /var/backups/etcd-$(date +%F).db

# Vérification
etcdctl --write-out=table snapshot status /var/backups/etcd-*.db

# Restore (à faire sur node dédié, kube-apiserver stoppé)
etcdctl snapshot restore /var/backups/etcd.db \
  --data-dir=/var/lib/etcd-restore
# Puis modifier /etc/kubernetes/manifests/etcd.yaml : hostPath --data-dir
```

## ⬆️ Upgrade kubeadm — procédure figée

```bash
# 1. Sur control plane primaire
apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.35.x-*
apt-mark hold kubeadm
kubeadm upgrade plan
kubeadm upgrade apply v1.35.x

# 2. Drain le node
k drain <cp1> --ignore-daemonsets

# 3. Upgrade kubelet + kubectl
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.x-* kubectl=1.35.x-*
apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet

# 4. Uncordon
k uncordon <cp1>

# 5. Répéter sur autres control plane (kubeadm upgrade node) puis workers
```

> ⚠️ **Ordre du `drain` — piège LFS258 vs officiel**
> - **Doc officielle (kubernetes.io)** : `apt kubeadm` → `upgrade plan` → `upgrade apply` → **drain** → `apt kubelet/kubectl` + restart → `uncordon`. Le drain vient **APRÈS** `upgrade apply`.
> - **LFS258** : place le drain **AVANT** `plan`/`apply` (plus prudent, mais non aligné).
> - 👉 **En exam, suis l'ordre officiel** (ci-dessus). Le `kube-apiserver` est un static Pod → il tourne même node drainé, donc drainer avant `apply` n'apporte rien ; le drain sert à protéger les workloads **avant l'upgrade du kubelet**.
>
> **CP vs workers** :
> - 1er control plane → `kubeadm upgrade apply v1.35.x`
> - autres CP + **tous les workers** → `kubeadm upgrade node` (pas de `plan`, pas de `apply`)

## 🎯 Timing exam

- 2 h · ~15-20 questions · **flag** les questions coûteuses (`⚑`) et reviens à la fin
- `--dry-run=client -o yaml` **toujours** pour les créations complexes
- `kubectl explain <res>.<field> --recursive` **avant** de chercher la doc
- Verrouille systématiquement le contexte : `k config use-context <ctx>`
