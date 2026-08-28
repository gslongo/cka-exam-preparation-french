# 🧪 Lab setup — Cluster kubeadm local (K8s 1.34 → upgrade 1.35)

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
# cp1    Ready    control-plane   5m    v1.34.x   ← init en 1.34 (upgrade vers 1.35 à pratiquer)
# w1     Ready    <none>          3m    v1.34.x
# w2     Ready    <none>          3m    v1.34.x

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

## 📝 Examen blanc CKA

Le dossier [mock-exam/](mock-exam/) contient les examens blancs **auto-corrigés** (16 tâches, 100 pts, seuil 66 %, ~2 h chacun), un sous-dossier par sujet : [exam-01/](mock-exam/exam-01/) (intermédiaire) et [exam-02/](mock-exam/exam-02/) (**avancé**). Vue d'ensemble, pondération et liste des fichiers : voir le [README général](../README.md). Ici, le **mode d'emploi** sur le lab (remplace `exam-01` par `exam-02` pour le sujet avancé) :

```bash
# 1. Préparer l'environnement (sur cp1, via le dossier synchronisé /vagrant)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"

# 2. Composer ~2 h sur le cluster en suivant mock-exam/exam-01/EXAM.md
#    (la plupart des tâches sur cp1 ; la tâche « static pod » se traite sur w1)

# 3. Se corriger
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/grade.sh"

# 4. Recommencer à zéro (ré-amorce l'état de départ)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"
```

> 💡 `setup.sh` (lancé sur cp1) nettoie les namespaces d'exam, le PV, le label de `w1`, dé-cordonne les workers et supprime le snapshot etcd. Le **static pod** vit sur le disque de `w1` : pour repartir propre, le retirer à la main → `vagrant ssh w1 -c "sudo rm -f /etc/kubernetes/manifests/static-web.yaml"`.
> Aucun `vagrant destroy` n'est requis pour ces examens (tout se joue au niveau des objets K8s) ; pour l'**exam-02**, `setup.sh` retire en plus le taint de `w1` et le ClusterRole/Binding créés.

## 🧪 Labs thématiques

Le dossier [labs/](labs/) contient des **labs ciblés** sur un thème (à la différence des examens blancs qui balaient tout le programme). Chacun garde la même mécanique **auto-corrigée** (`LAB.md` + `setup.sh` + `grade.sh` + `solutions/`) mais sans limite de temps.

- [labs/lab-services-ingress-gateway/](labs/lab-services-ingress-gateway/) — **Services · Ingress · Gateway API** (100 pts, objectif 75 %). Services testés en direct (connectivité) ; Ingress/Gateway notés sur l'objet (aucun contrôleur installé). Installe au besoin les CRD Gateway API.
- [labs/lab-storage-config-multicontainer/](labs/lab-storage-config-multicontainer/) — **Stockage · ConfigMap/Secrets · Sidecars** (100 pts, objectif 75 %). Binding statique PV/PVC et Pods testés en direct ; StorageClass notée sur l'objet (aucun provisioner CSI). Inclut la récupération d'un PV `Released` (claimRef) et le sidecar natif (K8s 1.29+).
- [labs/lab-troubleshooting/](labs/lab-troubleshooting/) — **🔧 Troubleshooting transverse** (100 pts, objectif 75 %). **Tout est cassé au départ**, à diagnostiquer et réparer : 16 pannes réparties sur les 4 domaines (RBAC, static pod sur `cp1`, noeud `w1` hors service, finalizer, `ImagePull`/`CrashLoop`/config, `Pending`, readiness, selector/`targetPort`/NetworkPolicy/DNS, PVC). Tout est réparable depuis `cp1` + `kubectl` et testé en direct.

```bash
# Préparer / se corriger (même principe que les examens)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"

# Lab Stockage · ConfigMap/Secrets · Sidecars
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"

# Lab Troubleshooting transverse (tout est cassé, à réparer)
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/setup.sh"
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/grade.sh"
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
| **Kubernetes** | 1.34.x | kubeadm + kubelet + kubectl — **init en 1.34** pour pratiquer l'upgrade → 1.35 (version exam CKA) |
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
- **Swap** : désactivé automatiquement par le script (K8s 1.34+ supporte swap mais off = plus simple).
- **Ubuntu box GPG issue** : si `apt-get update` échoue à cause d'une clé, `vagrant reload --provision` suffit généralement.

## Rebuild du cluster from scratch

```bash
vagrant destroy -f
vagrant up --no-parallel
```

Prévoir ~10 min. Le box Ubuntu est cached après le 1er download.
