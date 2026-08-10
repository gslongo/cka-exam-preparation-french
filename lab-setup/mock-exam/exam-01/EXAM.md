# 🧪 CKA — Examen blanc (lab kubeadm)

> **Format réel CKA** : 2 h · tâches pratiques · **passage 66 %** · barème pondéré ci-dessous.
> Environnement : le cluster du lab (`cp1` + `w1` + `w2`, K8s 1.34, Calico).
> **Les solutions ne sont PAS dans ce fichier** → voir `solutions/SOLUTIONS.md` (à n'ouvrir qu'après).

---

## ⚙️ Mise en place (avant de démarrer le chrono)

```bash
# Depuis la machine hôte, dans lab-setup/

# 0. (Re)déployer le lab si besoin — cluster 1 CP + 2 workers (K8s 1.34, Calico)
vagrant up --no-parallel        # 1re fois : monte les VMs ; sinon démarre celles arrêtées
vagrant ssh cp1 -c "kubectl get nodes"   # valider : cp1/w1/w2 Ready avant de continuer

# 1. Amorcer l'environnement d'examen (namespaces + ressources cassées)
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"

# 2. Se connecter au control plane pour composer
vagrant ssh cp1
```

Toutes les commandes se font depuis `cp1` (kubeconfig admin déjà en place).
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

> 🏷️ **RÈGLE D'OR — le namespace compte pour des points.** Chaque tâche impose un namespace précis (badge `🏷️ ns` dans son titre). Une ressource correcte mais **créée dans le mauvais namespace = 0 point** (le vrai CKA vérifie le namespace à la lettre). Réflexe : mets **`-n <namespace>`** sur *chaque* commande, et vérifie avec `kubectl -n <namespace> get …` avant de passer à la suite. Les tâches **T2, T3, T4** agissent au niveau **node/cluster** (pas de namespace).

---

## 🏛️ Cluster Architecture (25 pts)

### T1 — RBAC (7 pts) · 🏷️ **ns `rbac-test`**
Dans le namespace `rbac-test` :
1. Crée un **ServiceAccount** `deploy-bot`.
2. Crée un **Role** `pod-reader` autorisant uniquement `get`, `list`, `watch` sur les **pods**.
3. Lie les deux avec un **RoleBinding** `deploy-bot-read`.

> Attendu : `deploy-bot` peut **lister** les pods de `rbac-test` mais **ne peut pas** les supprimer.

### T2 — Sauvegarde etcd (8 pts) · sur `cp1`
Réalise un **snapshot etcd** du cluster et enregistre-le dans le fichier **`/opt/etcd-backup.db`** sur `cp1`.
Utilise les certificats du control plane (`/etc/kubernetes/pki/etcd/…`).

> Attendu : `/opt/etcd-backup.db` existe et est un snapshot etcd **valide**.

### T3 — Static Pod (5 pts) · sur `w1`
Sur le node **`w1`**, crée un **static pod** nommé `static-web` (image `nginx:1.29-alpine`) via le répertoire des manifests statiques du kubelet.

> Attendu : un pod **`static-web-w1`** apparaît `Running` dans le namespace `default`.

### T4 — Maintenance node (5 pts)
Le node **`w2`** doit partir en maintenance. Marque-le pour qu'**aucun nouveau pod** ne s'y planifie (sans le supprimer ni supprimer ses pods existants).

> Attendu : `w2` en état `SchedulingDisabled`.

---

## 📦 Workloads & Scheduling (15 pts)

### T5 — Deployment + scale (5 pts) · 🏷️ **ns `workloads`**
Crée un Deployment **`web`** : image **`nginx:1.29-alpine`**, **3 réplicas**, `containerPort` 80.

> Attendu : 3 pods `Ready`, bonne image.

### T6 — ConfigMap → variable d'env (5 pts) · 🏷️ **ns `workloads`**
1. Crée une **ConfigMap** `app-config` avec la clé **`APP_COLOR=blue`**.
2. Crée un **Pod** `color-pod` (image `busybox:1.36`, commande `sleep 100000`) qui expose la variable d'environnement **`APP_COLOR`** à partir de cette ConfigMap.

> Attendu : `color-pod` `Running`, variable `APP_COLOR` injectée depuis la ConfigMap.

### T7 — Placement par label (5 pts) · 🏷️ **ns `workloads`**
1. Ajoute le label **`disktype=ssd`** au node **`w1`**.
2. Crée un Pod **`ssd-pod`** (image `nginx:1.29-alpine`) qui, via un **`nodeSelector`**, ne peut se planifier **que** sur un node `disktype=ssd`.

> Attendu : `ssd-pod` `Running` **sur `w1`**.

---

## 🌐 Services & Networking (20 pts)

### T8 — Service ClusterIP (5 pts) · 🏷️ **ns `workloads`**
Expose le Deployment `web` (T5) via un Service **ClusterIP** nommé **`web-svc`**, port **80** → targetPort **80**.

> Attendu : `web-svc` de type ClusterIP avec **3 endpoints**.

### T9 — Service NodePort (5 pts) · 🏷️ **ns `workloads`**
Crée un Service **NodePort** nommé **`web-np`** pour le Deployment `web`, port **80**, **nodePort `30080`**.

> Attendu : `web-np` type NodePort, nodePort `30080`, endpoints présents.

### T10 — NetworkPolicy (10 pts) · 🏷️ **ns `netpol`**
Le namespace `netpol` contient déjà `backend` (label `app=backend`, écoute `:80`, Service `backend`), `frontend` (`app=frontend`) et `client` (`app=other`).
Crée une **NetworkPolicy** **`backend-allow-frontend`** qui : sur les pods `app=backend`, n'autorise le trafic **entrant** **que** depuis les pods `app=frontend`, sur le **port 80**.

> Attendu : `frontend` peut joindre `backend:80`, **`client` ne peut plus**.

---

## 💾 Storage (10 pts)

### T11 — PV + PVC (6 pts) · 🏷️ **ns `storage`**
1. Crée un **PersistentVolume** `pv-manual` : `1Gi`, `hostPath` `/mnt/data`, `accessModes: ReadWriteOnce`, `storageClassName: manual`.
2. Crée un **PVC** `pvc-manual` dans `storage` : `500Mi`, `ReadWriteOnce`, `storageClassName: manual`.

> Attendu : `pvc-manual` est **`Bound`** à `pv-manual`.

### T12 — Pod monté sur le PVC (4 pts) · 🏷️ **ns `storage`**
Crée un Pod **`pv-pod`** (image `nginx:1.29-alpine`) qui monte le PVC `pvc-manual` sur **`/usr/share/nginx/html`**.

> Attendu : `pv-pod` `Running` avec le volume `pvc-manual` monté au bon chemin.

---

## 🔧 Troubleshooting (30 pts)

> Ces ressources sont **déjà déployées et cassées** par `setup.sh`. **Répare-les.**

### T13 — Pods qui ne démarrent pas (6 pts) · 🏷️ **ns `trouble`**
Le Deployment **`tshoot-web`** est en `ImagePullBackOff`. Corrige-le pour qu'il tourne (image valide **`nginx:1.29-alpine`**).

> Attendu : `tshoot-web` disponible, pods `Running`.

### T14 — Service sans endpoints (8 pts) · 🏷️ **ns `trouble`**
Le Service **`api-svc`** ne renvoie aucun endpoint alors que le Deployment `api` tourne. Trouve et corrige la cause.

> Attendu : `api-svc` a des **endpoints** (les pods `api`).

### T15 — Pod `Pending` (8 pts) · 🏷️ **ns `trouble`**
Le Pod **`hungry`** reste `Pending` et ne se planifie jamais. Fais en sorte qu'il tourne (le pod doit toujours s'appeler `hungry`, image `nginx:1.29-alpine`).

> Attendu : un pod `hungry` `Running` dans `trouble`.

### T16 — Deployment bloqué en création (8 pts) · 🏷️ **ns `trouble`**
Le Deployment **`cfg-app`** est bloqué : il monte une ConfigMap **`cfg-app-config`** qui n'existe pas. Crée cette ConfigMap avec une clé **`app.properties`** contenant `mode=prod`, pour débloquer les pods.

> Attendu : ConfigMap `cfg-app-config` (clé `app.properties`) présente **et** pods `cfg-app` `Running`.

---

## ✅ Correction

```bash
bash /vagrant/mock-exam/exam-01/grade.sh
```

Le script affiche le détail par tâche, le score par domaine, et le **total /100** avec verdict (**≥ 66 = réussi**).
