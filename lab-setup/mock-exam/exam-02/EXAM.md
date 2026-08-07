# 🧪 CKA — Examen blanc n°2 · niveau avancé (lab kubeadm)

> **Format réel CKA** : 2 h · tâches pratiques · **passage 66 %** · barème pondéré ci-dessous.
> Environnement : le cluster du lab (`cp1` + `w1` + `w2`, K8s 1.34, Calico).
> **Plus corsé que l'exam-01** : RBAC cluster-scoped, scheduling manuel, taints/tolerations, Secrets, NetworkPolicy default-deny, `reclaimPolicy`/`subPath`, et un troubleshooting moins évident (sonde, dérive de labels, contrainte de placement, Secret manquant).
> **Les solutions ne sont PAS dans ce fichier** → voir `solutions/SOLUTIONS.md` (à n'ouvrir qu'après).

---

## ⚙️ Mise en place (avant de démarrer le chrono)

```bash
# Depuis la machine hôte, dans lab-setup/

# 0. Cluster sain requis (cp1+w1+w2 Ready). Un « vagrant destroy » N'EST PAS
#    nécessaire pour cet examen : tout se joue au niveau des objets K8s.
#    Si ton cluster est dans un état incertain (labo précédent, composant cassé),
#    repars propre :  vagrant destroy -f && vagrant up --no-parallel
vagrant ssh cp1 -c "kubectl get nodes"   # valider : cp1/w1/w2 Ready avant de continuer

# 1. Amorcer l'examen n°2 (namespaces + ressources cassées)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/setup.sh"

# 2. Se connecter au control plane pour composer
vagrant ssh cp1
```

Toutes les commandes se font depuis `cp1` (kubeconfig admin déjà en place), **sauf T3** (static pod, sur `w1`).
Alias utiles déjà chargés : `k`, `$do` (`--dry-run=client -o yaml`), `$now`.

## 📏 Règles

- **Un seul cluster** ici (pas de `use-context` à faire), mais **lis bien le namespace** imposé par chaque tâche.
- Tu peux utiliser la doc officielle `kubernetes.io/docs` (comme à l'exam).
- Le barème est **automatique** : chaque tâche est vérifiée par `grade.sh`. Respecte **noms, namespaces, labels, ports** à la lettre.
- **Total : 100 points** répartis selon les poids réels du curriculum. Objectif : **≥ 66**.

| Domaine | Poids | Tâches |
|---|---|---|
| Cluster Architecture | 25 | T1–T4 |
| Workloads & Scheduling | 15 | T5–T7 |
| Services & Networking | 20 | T8–T10 |
| Storage | 10 | T11–T12 |
| Troubleshooting | 30 | T13–T16 |

---

## 🏛️ Cluster Architecture (25 pts)

### T1 — RBAC cluster-scoped (7 pts) · namespace `platform`
1. Crée un **ServiceAccount** `ci-bot` dans le namespace `platform`.
2. Crée un **ClusterRole** `deploy-admin` autorisant `get`, `list`, `watch`, `create`, `update`, `patch` sur les **deployments** (`apps`).
3. Lie-les avec un **ClusterRoleBinding** `ci-bot-deploy` (portée cluster).

> Attendu : `ci-bot` peut **créer un Deployment dans n'importe quel namespace** mais **ne peut pas** supprimer de node.

### T2 — Sauvegarde etcd (8 pts) · sur `cp1`
Réalise un **snapshot etcd** du cluster et enregistre-le dans **`/opt/etcd-backup.db`** sur `cp1`, avec les certificats du control plane (`/etc/kubernetes/pki/etcd/…`).

> Attendu : `/opt/etcd-backup.db` existe et est un snapshot etcd **valide**.

### T3 — Static Pod avec label (5 pts) · sur `w1`
Sur le node **`w1`**, crée un **static pod** nommé `static-web` (image `nginx:1.29-alpine`, `containerPort` 80) via le répertoire des manifests statiques du kubelet. Le pod doit porter le **label `role=cache`**.

> Attendu : un pod **`static-web-w1`** `Running` (namespace `default`) sur `w1`, avec le label `role=cache`.

### T4 — Scheduling manuel (5 pts) · namespace `apps`
Sans passer par le scheduler, place un Pod **`pinned`** (image `nginx:1.29-alpine`) **directement sur le node `w2`**.

> Attendu : `pinned` `Running`, `spec.nodeName = w2`.

---

## 📦 Workloads & Scheduling (15 pts)

### T5 — Deployment + stratégie de rollout (5 pts) · namespace `apps`
Crée un Deployment **`api`** : image **`nginx:1.29-alpine`**, **3 réplicas**, `containerPort` 80, `requests` `cpu=50m`/`memory=32Mi`, et une stratégie **RollingUpdate** avec **`maxUnavailable: 0`** (et `maxSurge: 1`).

> Attendu : 3 pods `Ready`, image correcte, `maxUnavailable = 0`.

### T6 — Secret → variable d'env (5 pts) · namespace `apps`
1. Crée un **Secret** `app-secret` avec la clé **`TOKEN=s3cr3t`**.
2. Crée un **Pod** `secret-pod` (image `busybox:1.36`, commande `sleep 100000`) qui expose la variable d'environnement **`TOKEN`** à partir de ce Secret.

> Attendu : `secret-pod` `Running`, variable `TOKEN` injectée depuis le Secret `app-secret`.

### T7 — Taint + toleration (5 pts) · namespace `apps`
1. Ajoute au node **`w1`** le taint **`dedicated=cka:NoSchedule`**.
2. Crée un Pod **`tolerant`** (image `nginx:1.29-alpine`) qui **tolère** ce taint **et** se planifie **sur `w1`**.

> Attendu : `w1` porte le taint `dedicated=cka:NoSchedule` ; `tolerant` `Running` **sur `w1`** avec la toleration correspondante.

---

## 🌐 Services & Networking (20 pts)

### T8 — Service ClusterIP (5 pts) · namespace `apps`
Expose le Deployment `api` (T5) via un Service **ClusterIP** nommé **`api-svc`**, port **80** → targetPort **80**.

> Attendu : `api-svc` de type ClusterIP avec **3 endpoints**.

### T9 — Service NodePort (5 pts) · namespace `apps`
Crée un Service **NodePort** nommé **`api-np`** pour le Deployment `api`, port **80**, **nodePort `30090`**.

> Attendu : `api-np` type NodePort, nodePort `30090`, endpoints présents.

### T10 — NetworkPolicy default-deny + allow (10 pts) · namespace `secure`
Le namespace `secure` contient déjà `db` (label `app=db`, écoute `:80`, Service `db`), `web` (`app=web`) et `scanner` (`app=other`). Au départ, tout le monde peut joindre `db`.
1. Crée une **NetworkPolicy** **`default-deny-ingress`** qui **bloque tout l'ingress** du namespace (podSelector vide, `policyTypes: [Ingress]`).
2. Crée une **NetworkPolicy** **`allow-web-to-db`** qui autorise l'ingress vers `app=db`, **uniquement** depuis `app=web`, sur le **port 80**.

> Attendu : `web` peut joindre `db:80`, **`scanner` ne peut plus**.

---

## 💾 Storage (10 pts)

### T11 — PV (Retain) + PVC (6 pts) · namespace `storage`
1. Crée un **PersistentVolume** `pv-fast` : `2Gi`, `hostPath` `/mnt/data-02` (**`type: DirectoryOrCreate`**, pour que le répertoire soit créé sur le node), `accessModes: ReadWriteOnce`, `storageClassName: fast`, **`persistentVolumeReclaimPolicy: Retain`**.
2. Crée un **PVC** `data` dans `storage` : `1Gi`, `ReadWriteOnce`, `storageClassName: fast`.

> Attendu : `data` est **`Bound`** à `pv-fast`, dont la politique de récupération est **`Retain`**.

### T12 — Pod monté via subPath (4 pts) · namespace `storage`
Crée un Pod **`app`** (image `nginx:1.29-alpine`) qui monte le PVC `data` sur **`/usr/share/nginx/html`** en utilisant **`subPath: html`**.

> Attendu : `app` `Running`, volume `data` monté au bon chemin avec `subPath: html`.

---

## 🔧 Troubleshooting (30 pts)

> Ces ressources sont **déjà déployées et cassées** par `setup.sh`. **Répare-les.**

### T13 — Deployment jamais `Ready` (6 pts) · namespace `trouble`
Le Deployment **`frontend`** tourne mais reste `0` disponible : sa **readinessProbe** interroge le mauvais port. Corrige-la.

> Attendu : `frontend` disponible (pods `Ready`).

### T14 — Service sans endpoints (8 pts) · namespace `trouble`
Le Service **`store-svc`** ne renvoie aucun endpoint alors que le Deployment `store` tourne. Trouve et corrige la cause (cohérence **selector ↔ labels**).

> Attendu : `store-svc` a des **endpoints**.

### T15 — Pod `Pending` (8 pts) · namespace `trouble`
Le Pod **`stuck`** reste `Pending` : il exige une contrainte de placement qu'aucun node ne satisfait. Fais en sorte qu'il tourne (le pod doit toujours s'appeler `stuck`, image `nginx:1.29-alpine`).

> Attendu : un pod `stuck` `Running` dans `trouble`.

### T16 — Deployment bloqué en création (8 pts) · namespace `trouble`
Le Deployment **`billing`** est bloqué : il référence une variable d'env issue d'un **Secret `billing-secret`** qui n'existe pas. Crée ce Secret avec la clé **`API_KEY`** (valeur au choix) pour débloquer les pods.

> Attendu : Secret `billing-secret` (clé `API_KEY`) présent **et** pods `billing` `Running`.

---

## ✅ Correction

```bash
bash /vagrant/mock-exam/exam-02/grade.sh
```

Le script affiche le détail par tâche (avec le **symptôme observé** en cas d'échec, jamais la solution), le score par domaine, et le **total /100** avec verdict (**≥ 66 = réussi**).
