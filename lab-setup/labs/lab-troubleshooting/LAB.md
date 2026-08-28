# 🔧 Lab — Troubleshooting transverse (tous domaines)

> **Lab thématique** (pas un examen blanc) : du **troubleshooting pur**. Au départ **tout est cassé** —
> à toi de **diagnostiquer et réparer**. Les **16 pannes** couvrent **les 4 domaines techniques** du CKA
> (Architecture/Nodes, Workloads/Scheduling, Services/Networking, Storage) : le message est justement que
> *le troubleshooting est transverse*.
> **100 pts**, objectif **≥ 75 %**. Pas de limite de temps — c'est un lab d'entraînement.

> 🧩 **Indépendance** : chaque panne vit dans **son propre namespace** (`ts-arch`, `ts-nodes`, `ts-work`,
> `ts-net`, `ts-netpol`, `ts-storage`) — tu peux en traiter **une seule** sans casser les autres. **Deux
> exceptions** touchent au **noeud** et sont signalées : **A2** se répare **sur `cp1`** (`vagrant ssh cp1`,
> manifest statique), **A3** concerne l'état du noeud **`w1`** (réparable via `kubectl`). Aucune tâche ne
> dépend d'une autre.

> 🔎 **Tout est vérifié en direct** : le grader lit le **statut réel** (`Running`, `Bound`, endpoints) et
> **`exec`** dans les Pods pour tester le **trafic** (services, NetworkPolicy) et le **DNS**. Il n'affiche
> jamais la solution, seulement le **symptôme** observé.

## Mise en place
```bash
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/setup.sh"   # casse l'environnement (idempotent)
# … tu répares les pannes …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/grade.sh"   # correction (lecture seule)
```
> `setup.sh` est **idempotent** : il **annule d'abord** toute réparation d'un run précédent (noeuds
> décordonnés/dé-taintés, manifest statique retiré de `cp1`, finalizers débloqués), recrée les namespaces
> et re-sème l'état **cassé**. Les solutions sont dans [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — à n'ouvrir qu'après.

> 🧭 **Méthode** (rappel [fiche 05](../../../05-troubleshooting.md)) : `describe` → **Events** d'abord ;
> `logs` / `logs -p` ; `Pending` ⇒ `describe pod` (ressources / taint / nodeSelector / cordon) ;
> « pas de trafic » ⇒ `get endpoints` (selector/probes), `targetPort`, NetworkPolicy, DNS ; noeud ⇒ `describe node`.

---

## 🏛️ Domaine ARCH — Cluster Architecture & Nodes (28 pts)

### A1 — RBAC : un ServiceAccount sans droits (8 pts) · ns `ts-arch`
Le *ServiceAccount* **`deploy-bot`** doit pouvoir **lister** (`get`/`list`) les Pods de `ts-arch`, mais
`kubectl auth can-i` répond **`no`**. Le *Role* et la *RoleBinding* existent pourtant. Répare l'attribution.

> 💡 `kubectl -n ts-arch auth can-i list pods --as=system:serviceaccount:ts-arch:deploy-bot`.
> Compare le **sujet** de la RoleBinding au SA réel.
> Objectif : `deploy-bot` peut **`list`** les pods mais **pas `delete`** (ne sur-attribue pas).

### A2 — Static pod cassé sur `cp1` (8 pts) · ns `default` · **sur le noeud `cp1`**
Le pod statique **`ts-static-cp1`** (dans `default`) n'arrive pas à démarrer. Corrige-le **sur le noeud
`cp1`** pour qu'il passe `Running`.

> 💡 `kubectl describe pod ts-static-cp1`. Un static pod se corrige **dans `/etc/kubernetes/manifests/`
> sur le noeud** (pas via `kubectl`). Le kubelet recharge tout seul.
> Objectif : `ts-static-cp1` **`Running`** avec une image valide.

### A3 — Noeud `w1` « hors service » (8 pts) · ns `ts-nodes`
Le *Deployment* **`billing`** (namespace `ts-nodes`) reste à **0 disponible** : ses pods sont épinglés sur
`w1`, mais **`w1` est en maintenance**. Remets le service en route.

> 💡 `kubectl -n ts-nodes describe pod -l app=billing` puis `kubectl describe node w1`. Il peut y avoir
> **plusieurs blocages cumulés** sur le noeud. (Effets de taint : `NoSchedule` / `PreferNoSchedule` / `NoExecute`.)
> Objectif : `billing` a **≥ 1 réplica disponible**.

### A4 — Objet coincé en `Terminating` (4 pts) · ns `ts-arch`
La *ConfigMap* **`stuck-cm`** de `ts-arch` a été supprimée mais reste **`Terminating`** indéfiniment.
Fais en sorte qu'elle **disparaisse** réellement.

> 💡 `kubectl -n ts-arch get cm stuck-cm -o yaml` → regarde `metadata.finalizers` + `deletionTimestamp`.
> Objectif : `stuck-cm` n'existe plus.

---

## 📦 Domaine WORK — Workloads & Scheduling (32 pts) · ns `ts-work`

### W1 — `ImagePullBackOff` (6 pts)
Le *Deployment* **`web`** ne démarre pas (image introuvable). Corrige-le.
> 💡 `describe deploy web`. Objectif : `web` **disponible** (≥ 1 réplica, image valide).

### W2 — `CrashLoopBackOff` (6 pts)
Le *Pod* **`crasher`** redémarre en boucle. Rends-le durablement `Running`.
> 💡 `kubectl -n ts-work logs crasher -p`. La commande du conteneur est en cause.
> Objectif : `crasher` **`Running`** (stable).

### W3 — `CreateContainerConfigError` (6 pts)
Le *Pod* **`checkout`** ne crée pas son conteneur : il injecte `DB_PASSWORD` depuis un *Secret*, mais
**une clé manque**. Répare pour qu'il démarre avec la variable présente.
> 💡 `describe pod checkout` (Events). Objectif : `checkout` **`Running`** et `DB_PASSWORD` bien injectée.

### W4 — `Pending` (ressources) (5 pts)
Le *Pod* **`report`** reste `Pending` : personne ne peut l'héberger. Rends-le `Running`.
> 💡 `describe pod report` → `Insufficient memory/cpu`. Objectif : `report` **`Running`**.

### W5 — `Pending` (contrainte de placement) (5 pts)
Le *Pod* **`analytics`** reste `Pending` à cause d'une **contrainte de placement** qu'aucun noeud ne
satisfait. Rends-le `Running`.
> 💡 `describe pod analytics` → `didn't match node selector`. Objectif : `analytics` **`Running`**.

### W6 — Pods `Running` mais jamais `Ready` (4 pts)
Le *Deployment* **`frontend`** a ses pods `Running` mais **`0/1 READY`** — donc aucun trafic. Corrige la
cause pour qu'ils deviennent `Ready`.
> 💡 `describe pod -l app=frontend` → section `Readiness`. Objectif : `frontend` a **≥ 1 réplica Ready**.

---

## 🌐 Domaine NET — Services & Networking (26 pts)

### N1 — Service sans endpoints (7 pts) · ns `ts-net`
Le *Service* **`api-svc`** n'a **aucun endpoint** alors que le Deployment `api` tourne. Rétablis-les.
> 💡 `kubectl -n ts-net get endpoints api-svc` + `get pods --show-labels`.
> Objectif : `api-svc` a **≥ 1 endpoint**.

### N2 — Service qui ne route pas (7 pts) · ns `ts-net`
Le *Service* **`shop-svc`** a bien des endpoints, mais un `wget` depuis **`shop-client`** échoue. Répare
le routage.
> 💡 `kubectl -n ts-net exec shop-client -- wget -T4 -qO- http://shop-svc`. Compare `port`/`targetPort` au port réel du conteneur.
> Objectif : `shop-client` **joint** `shop-svc`.

### N3 — Trafic bloqué par une NetworkPolicy (7 pts) · ns `ts-netpol`
Dans `ts-netpol`, le Pod **`client`** ne peut plus joindre **`backend`** : une *NetworkPolicy* bloque tout.
Autorise le flux **`client → backend`** (sans tout ré-ouvrir).
> 💡 `kubectl -n ts-netpol get netpol` ; teste `exec client -- wget -T4 -qO- http://backend`.
> Objectif : `client` **joint** `backend` (le trafic passe).

### N4 — Résolution DNS cassée (5 pts) · ns `ts-net`
Le *Pod* **`dns-broken`** ne résout **aucun** service du cluster (`*.svc.cluster.local`). Répare sa
résolution DNS.
> 💡 `kubectl -n ts-net exec dns-broken -- nslookup kubernetes.default` ; regarde `spec.dnsPolicy`.
> Objectif : `dns-broken` **résout** `kubernetes.default.svc.cluster.local`.

---

## 💾 Domaine STO — Storage (14 pts) · ns `ts-storage`

### S1 — PVC bloquée en `Pending` (7 pts)
La *PVC* **`data`** reste `Pending` : elle ne trouve pas de volume. Fais en sorte qu'elle se **lie**.
> 💡 `describe pvc data`. Il existe un PV `pv-small` — compare sa `storageClassName` à celle demandée.
> Objectif : `data` est **`Bound`**.

### S2 — Pod bloqué : PVC manquante (7 pts)
Le *Pod* **`app`** reste en `ContainerCreating` : il monte une PVC qui **n'existe pas**. Répare pour qu'il
démarre (un PV `pv-app` est disponible).
> 💡 `describe pod app` → `persistentvolumeclaim "…" not found`.
> Objectif : `app` **`Running`**.

---

> 🧪 Ce lab est **extensible** : d'autres pannes classiques (kubelet `NotReady`, `etcd`/certificats,
> CoreDNS `Corefile`, `kube-proxy`) demandent un accès **système** aux workers et sont traitées dans les
> **examens blancs** (`lab-setup/mock-exam/`). Ici, tout est réparable depuis `cp1` + `kubectl`.
