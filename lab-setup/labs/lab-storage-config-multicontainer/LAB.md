# 💾 Lab — Stockage · ConfigMap/Secrets · Sidecars

> **Lab thématique** (pas un examen blanc) : il se concentre sur la **configuration et la
> persistance des workloads** — *stockage* (PV/PVC/StorageClass), *config* (ConfigMap/Secrets)
> et *Pods multi-conteneurs* (emptyDir partagé, sidecar natif).
> Les tâches sont **quasi indépendantes** et de difficulté progressive : tu peux en jouer une seule à la fois.
> **100 pts**, objectif **≥ 75 %**. Pas de limite de temps — c'est un lab d'entraînement.

> ⚠️ **Aucun provisioner dynamique (CSI) n'est installé** (cluster kubeadm nu). La *StorageClass* de A1
> est donc notée sur l'**objet** (ses champs), comme pour un Ingress sans contrôleur. En revanche, le
> **binding statique PV↔PVC** (hostPath) et les **Pods** sont testés **en direct** : le grader lit le
> statut réel (`Bound`, `Running`) et **exec** dans les Pods pour vérifier montages, variables d'env et
> fichiers partagés.

## Mise en place
```bash
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/setup.sh"   # sème l'état de départ
# … tu résous les tâches …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"   # correction (lecture seule)
```
> `setup.sh` est **idempotent** : il recrée les namespaces `storage-lab`, `config-lab`, `multi-lab`,
> (re)crée les *PersistentVolumes* `pv-data` et `pv-archive`, et laisse volontairement `pv-archive`
> en état **`Released`** (pour la tâche A4). Il nettoie tes réponses précédentes avant de re-semer.
> Les solutions sont dans [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — à n'ouvrir qu'après.

---

## 💾 Domaine A — Stockage persistant (40 pts) · Namespace `storage-lab`

### A1 — Créer une StorageClass (8 pts)
Crée une *StorageClass* nommée **`fast-local`** avec :

- provisioner **`example.com/fast-provisioner`** (illustratif — aucun contrôleur derrière) ;
- **`volumeBindingMode: WaitForFirstConsumer`** ;
- **`reclaimPolicy: Retain`** ;
- **`allowVolumeExpansion: true`**.

> 💡 Une *StorageClass* n'a **pas** de bloc `spec` : `provisioner`, `reclaimPolicy`, `volumeBindingMode`
> et `allowVolumeExpansion` sont des champs de **premier niveau**. `WaitForFirstConsumer` retarde la
> création du volume jusqu'à ce qu'un Pod consomme le PVC (utile pour la topologie multi-zones).
> Attendu : `fast-local` — provisioner `example.com/fast-provisioner`, `WaitForFirstConsumer`, `Retain`, expansion **activée**.

### A2 — Lier un PVC à un PV statique (10 pts)
Un *PersistentVolume* **`pv-data`** (hostPath, **5Gi**, `ReadWriteOnce`, `storageClassName: manual`)
existe déjà. Crée dans `storage-lab` un *PVC* **`app-data`** qui s'y lie :
**2Gi**, `ReadWriteOnce`, `storageClassName: manual`.

> 💡 Le binding **statique** ne dépend d'aucun provisioner : le contrôleur associe le PVC à un PV
> **compatible** (même `storageClassName`, `accessModes` inclus, capacité ≥ demande). Vérifie :
> `kubectl -n storage-lab get pvc app-data` (colonne `STATUS` = `Bound`, `VOLUME` = `pv-data`).
> Attendu : `app-data` est **`Bound`** et lié précisément à **`pv-data`**.

### A3 — Consommer le PVC dans un Pod (10 pts)
Crée un *Pod* **`app`** (image `busybox:1.36`, qui reste vivant — ex. `sleep 100000`) qui **monte**
le PVC `app-data` sur **`/data`**. Puis crée dans ce volume un fichier vide **`/data/ready`**.

> 💡 Deux morceaux : `spec.volumes[].persistentVolumeClaim.claimName: app-data` et, dans le conteneur,
> `volumeMounts[].mountPath: /data`. Le fichier se crée après démarrage : `kubectl -n storage-lab exec app -- touch /data/ready`.
> Attendu : `app` `Running`, volume adossé au PVC `app-data` monté sur `/data`, et le fichier `/data/ready` présent.

### A4 — Récupérer un PV bloqué en `Released` (12 pts)
Le *PersistentVolume* **`pv-archive`** (3Gi, `storageClassName: archive`, `reclaimPolicy: Retain`)
est coincé en **`Released`** : son ancien PVC a été supprimé mais le **`claimRef`** périmé empêche
tout nouveau binding. Rends-le réutilisable, puis lie-lui un nouveau PVC :

1. **Débloque** `pv-archive` pour qu'il repasse `Available` ;
2. crée un *PVC* **`archive`** dans `storage-lab` (`ReadWriteOnce`, **2Gi**, `storageClassName: archive`)
   qui se **lie** à `pv-archive`.

> 💡 `kubectl get pv pv-archive -o yaml` montre un bloc `spec.claimRef` (namespace + name + **uid** obsolète).
> Tant qu'il est présent avec un `uid` qui ne correspond à aucun PVC, le PV reste `Released`. Retire ce
> bloc (`kubectl edit pv pv-archive` → supprimer `claimRef`, ou `kubectl patch pv pv-archive --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'`).
> Attendu : `pv-archive` **n'est plus `Released`** (Available puis Bound) et le PVC `archive` est **`Bound`** à `pv-archive`.

---

## ⚙️ Domaine B — ConfigMap & Secrets (35 pts) · Namespace `config-lab`

### B1 — ConfigMap multi-clés (8 pts)
Crée une *ConfigMap* nommée **`app-config`** avec **trois** clés :

- **`APP_MODE=production`**
- **`LOG_LEVEL=info`**
- **`MAX_CONNECTIONS=100`**

> 💡 `kubectl -n config-lab create configmap app-config --from-literal=APP_MODE=production --from-literal=LOG_LEVEL=info --from-literal=MAX_CONNECTIONS=100`.
> Attendu : `app-config` contient les 3 clés/valeurs exactes.

### B2 — Secret Opaque (7 pts)
Crée un *Secret* **`db-credentials`** (type **`Opaque`**) avec :

- **`username=admin`**
- **`password=S3cr3t-pass`**

> 💡 `kubectl -n config-lab create secret generic db-credentials --from-literal=username=admin --from-literal=password=S3cr3t-pass`
> (les valeurs sont stockées **base64** — ce n'est pas du chiffrement).
> Attendu : `db-credentials` de type `Opaque`, `username` et `password` décodant vers les bonnes valeurs.

### B3 — Injecter la config en variables d'environnement (10 pts)
Crée un *Pod* **`api`** (image `busybox:1.36`, qui reste vivant) qui reçoit :

- **toutes** les clés de `app-config` comme variables d'env (**`envFrom`**) ;
- une variable **`DB_PASSWORD`** dont la valeur vient de la clé **`password`** du Secret `db-credentials` (**`secretKeyRef`**).

> 💡 `envFrom: [{ configMapRef: { name: app-config } }]` importe chaque clé comme variable homonyme.
> `DB_PASSWORD` se fait avec `env: [{ name: DB_PASSWORD, valueFrom: { secretKeyRef: { name: db-credentials, key: password } } }]`.
> Vérifie : `kubectl -n config-lab exec api -- printenv APP_MODE DB_PASSWORD`.
> Attendu : dans `api`, `APP_MODE=production`, `MAX_CONNECTIONS=100` (via `envFrom`) et `DB_PASSWORD=S3cr3t-pass` (via `secretKeyRef`).

### B4 — Monter une ConfigMap en volume (10 pts)
1. Crée une *ConfigMap* **`web-index`** avec une clé **`index.html`** dont le contenu contient la chaîne **`CKA Storage Lab`**.
2. Crée un *Pod* **`web`** (image `nginx:1.29-alpine`) qui **monte** `web-index` en **volume** sur **`/usr/share/nginx/html`** (la clé `index.html` devient donc le fichier servi).

> 💡 Une ConfigMap montée en volume expose **chaque clé comme un fichier** (`mountPath/<clé>`). Ici la
> clé `index.html` remplace la page par défaut de nginx. `spec.volumes[].configMap.name: web-index` +
> `volumeMounts[].mountPath: /usr/share/nginx/html`. Vérifie : `kubectl -n config-lab exec web -- cat /usr/share/nginx/html/index.html`.
> Attendu : `web` `Running`, et `/usr/share/nginx/html/index.html` contient bien `CKA Storage Lab`.

---

## 🧩 Domaine C — Sidecars & Pods multi-conteneurs (25 pts) · Namespace `multi-lab`

### C1 — Deux conteneurs partageant un `emptyDir` (13 pts)
Crée un *Pod* **`shared-logs`** avec **deux** conteneurs partageant un volume **`emptyDir`** monté sur
**`/var/log/app`** dans les deux :

- **`writer`** (`busybox:1.36`) écrit en continu dans **`/var/log/app/app.log`** (ex. la date chaque seconde) ;
- **`sidecar`** (`busybox:1.36`) **lit** ce même fichier (ex. `tail -f /var/log/app/app.log`).

> 💡 Un `emptyDir` est **partagé** entre les conteneurs d'un même Pod (durée de vie = celle du Pod).
> Monte le **même** volume aux deux conteneurs. Writer typique : `sh -c 'while true; do date >> /var/log/app/app.log; sleep 1; done'`.
> Attendu : `shared-logs` `Running` (2 conteneurs), `emptyDir` monté sur `/var/log/app` **des deux côtés**, et `/var/log/app/app.log` **non vide** (le sidecar voit ce qu'écrit le writer).

### C2 — Sidecar « natif » (initContainer `restartPolicy: Always`) (12 pts)
Crée un *Pod* **`web-agent`** avec :

- un conteneur principal **`web`** (`nginx:1.29-alpine`) ;
- un **sidecar natif** nommé **`log-agent`** (`busybox:1.36`, long-running — ex. `sleep 100000`),
  déclaré comme un **`initContainer`** portant **`restartPolicy: Always`**.

> 💡 Depuis K8s **1.29**, un `initContainer` avec `restartPolicy: Always` est un **sidecar natif** : il
> démarre **avant** les conteneurs principaux **et** reste en vie tout le long (contrairement à un
> initContainer classique qui doit se terminer). C'est le patron moderne recommandé (log shipper, proxy…).
> Attendu : `web-agent` `Running`, avec un `initContainer` `log-agent` dont `restartPolicy=Always` **toujours actif**, et le conteneur `web` démarré.

---

_Ce lab est extensible : dis « ajoute une tâche sur `<sujet>` » (ex. `projected volume`, `subPath`,
`immutable` ConfigMap/Secret, `defaultMode`/`items`, `docker-registry` secret, resize de PVC…)._
