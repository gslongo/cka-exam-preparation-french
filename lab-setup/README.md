# 🧪 Lab setup — Cluster kubeadm local (K8s 1.35)

> Provisionnement automatique d'un cluster **1 CP + 2 workers** sur ta machine hôte via Vagrant/VirtualBox. Reproduit l'environnement de l'exam CKA (kubeadm, containerd, Calico), impossible à tester sur EKS.

---

## Prérequis machine hôte

| Composant | Version min | Notes |
|---|---|---|
| **CPU** | 6 vCPU dispo | 2 par VM × 3 VMs |
| **RAM** | 6 Go dispo | 2 Go par VM × 3 VMs |
| **Disque** | 20 Go libres | ~7 Go / VM |
| **Vagrant** | 2.4+ | `brew install --cask vagrant` / `apt install vagrant` |
| **VirtualBox** | 7.0+ | Alternative : libvirt (adapter `Vagrantfile`) |

## Usage

```bash
cd lab-setup/

# 1. Monter le cluster (~10-15 min la 1re fois : download box + install)
vagrant up --no-parallel        # séquentiel pour que cp1 génère le token avant workers

# 2. SSH sur le control plane
vagrant ssh cp1

# --- dans la VM cp1 ---
kubectl get nodes
# NAME   STATUS   ROLES           AGE   VERSION
# cp1    Ready    control-plane   5m    v1.35.x
# w1     Ready    <none>          3m    v1.35.x
# w2     Ready    <none>          3m    v1.35.x

kubectl get pods -A          # tout Running (calico, coredns, kube-*)
```

## Commandes utiles

```bash
vagrant status                 # état des 3 VMs
vagrant halt                   # stop propre
vagrant up                     # redémarrer (sans reprovisioning)
vagrant reload --provision     # reboot + re-run scripts
vagrant destroy -f             # supprimer tout
vagrant ssh w1                 # SSH sur un worker
```

## Snapshot / restore (pour rejouer un lab)

```bash
# Après un cluster fonctionnel de base
vagrant snapshot save clean

# Après avoir cassé qqch pour t'entraîner
vagrant snapshot restore clean
```

## Reset complet du cluster K8s (sans détruire les VMs)

Sur cp1 puis chaque worker :
```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d ~/.kube
sudo iptables -F && sudo iptables -t nat -F
```
Puis relancer `sudo /vagrant/init-cp.sh` puis `sudo /vagrant/join-worker.sh` (workers).

## Ce qui est installé

| Composant | Version | Rôle |
|---|---|---|
| **Ubuntu** | 22.04 LTS (bento box) | OS |
| **containerd** | apt Ubuntu (~1.7) | Container runtime CRI |
| **Kubernetes** | 1.35.x | kubeadm + kubelet + kubectl (= version exam CKA) |
| **Calico** | v3.28.1 (via tigera-operator) | CNI + NetworkPolicy (**pas dispo sur EKS/VPC CNI par défaut**) |
| **CIDR Pods** | `10.244.0.0/16` | — |
| **CIDR Services** | `10.96.0.0/12` (défaut) | — |

## Réseau

| VM | IP privée | Rôle |
|---|---|---|
| `cp1` | `192.168.56.10` | control plane |
| `w1` | `192.168.56.11` | worker |
| `w2` | `192.168.56.12` | worker |

## ⚠️ Pièges connus

- **`vagrant up` sans `--no-parallel`** : les workers essaient de join avant que cp1 n'ait généré le token → échec. Utiliser `--no-parallel` la première fois.
- **Réseau host-only VirtualBox** : sur macOS récent, il faut autoriser VirtualBox dans Réglages Système > Confidentialité et Sécurité après la 1re install.
- **Swap** : désactivé automatiquement par le script (K8s 1.35 supporte swap mais off = plus simple).
- **Ubuntu box GPG issue** : si `apt-get update` échoue à cause d'une clé, `vagrant reload --provision` suffit généralement.

## Rebuild du cluster from scratch

```bash
vagrant destroy -f
vagrant up --no-parallel
```

Prévoir ~10 min. Le box Ubuntu est cached après le 1er download.
