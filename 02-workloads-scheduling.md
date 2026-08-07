# 02 — Workloads & Scheduling

> **CKA — 15 %** · Deployments, ReplicaSets, DaemonSets, StatefulSets, Jobs, scheduling, autoscaling.

<details open>
<summary>📑 Sommaire</summary>

- [🎯 Objectifs de l'exam](#-objectifs-de-lexam)
- [🧠 Concepts clés](#-concepts-clés)
  - [Le Pod — unité de base](#le-pod--unité-de-base)
  - [Hiérarchie des workloads](#hiérarchie-des-workloads)
  - [ReplicaSet — orphelinage & adoption (label-driven)](#replicaset--orphelinage--adoption-label-driven)
  - [Rolling update & rollback (Deployment)](#rolling-update--rollback-deployment)
  - [StatefulSet — spécificités](#statefulset--spécificités)
  - [Job / CronJob — spécificités](#job--cronjob--spécificités)
  - [DaemonSet — spécificités](#daemonset--spécificités)
  - [Scheduling](#scheduling)
  - [Requests, limits, QoS](#requests-limits-qos)
  - [securityContext (Pod & container)](#securitycontext-pod--container)
  - [ResourceQuota & LimitRange (par namespace)](#resourcequota--limitrange-par-namespace)
  - [HPA (Horizontal Pod Autoscaler)](#hpa-horizontal-pod-autoscaler)
  - [Manifest management](#manifest-management)
- [📋 Commandes essentielles](#-commandes-essentielles)
- [📄 YAML de référence](#-yaml-de-référence)
- [⚠️ Pièges fréquents](#️-pièges-fréquents)
  - [Deployments](#deployments)
  - [StatefulSet](#statefulset)
  - [DaemonSet](#daemonset)
  - [Scheduling](#scheduling-1)
  - [Resources](#resources)
- [🔗 Docs officielles autorisées](#-docs-officielles-autorisées)

</details>

## 🎯 Objectifs de l'exam

- Comprendre les primitives de déploiement (rolling updates, rollbacks)
- Utiliser `ConfigMap`/`Secret` pour la config (angle CKA = cluster/admin)
- Connaître le sizing / `requests` / `limits` d'un workload
- Comprendre les concepts d'application self-healing et d'autoscaling (HPA)
- Gérer manifests et outils courants (Helm, Kustomize) — connaissance conceptuelle

## 🧠 Concepts clés

### Le Pod — unité de base

- **Plus petite unité déployable** de K8s (jamais un conteneur seul). Analogie « peas in a pod ».
- **1 IP par Pod**, partagée par tous ses conteneurs → ils communiquent via **`localhost`**, IPC ou un **volume partagé**.
- Design par défaut : **1 conteneur applicatif par Pod** (one-process-per-container).
- Les conteneurs d'un Pod **démarrent en parallèle** → **aucun ordre garanti**. Pour forcer une séquence (setup, migration…) → **`initContainers`** (s'exécutent l'un après l'autre, jusqu'au succès, **avant** les conteneurs principaux).
- **Patterns multi-conteneurs** (sidecar / ambassador / adapter) = des **rôles** de conception, **pas** des champs K8s :
  - **sidecar** : conteneur secondaire d'appui (log shipper, proxy) — cf. [Q12](QUESTIONS-EXAMEN.md).
  - **ambassador** : proxy vers un service externe.
  - **adapter** : normalise la sortie de l'app (ex: format de métriques).

> 💡 **Sidecar « natif »** (K8s 1.29+) = un `initContainer` avec `restartPolicy: Always` → démarre avant les conteneurs principaux **et** reste en vie tout le long.

> 💡 **initContainers — pattern « attendre une dépendance »** : run-to-completion, redémarrés jusqu'au succès, **bloquent** les conteneurs principaux tant qu'ils échouent.
> ```yaml
> spec:
>   initContainers:
>   - name: wait-db
>     image: busybox
>     command: ['sh','-c','until nc -z db 5432; do echo waiting; sleep 5; done']
>   containers:
>   - name: main-app
>     image: myapp
> ```
> Chaque `initContainer` a **ses propres** image, volumes et `securityContext` → il peut embarquer des outils absents de l'app et exécuter des tâches sensibles (perms élevées) sans les donner au conteneur principal.

### Hiérarchie des workloads

```mermaid
graph TD
    D[Deployment] -->|manage| RS[ReplicaSet]
    RS -->|create| P1[Pod]
    RS -->|create| P2[Pod]
    RS -->|create| P3[Pod]
    DS[DaemonSet] -->|one per node| PN[Pod]
    SS[StatefulSet] -->|ordered| SP0[Pod-0]
    SS -->|ordered| SP1[Pod-1]
    J[Job] --> PJ[Pod terminal]
    CJ[CronJob] --> J
```

| Controller | Usage | Identité stable | Ordre |
|---|---|---|---|
| `Deployment` | Stateless apps | ❌ | ❌ |
| `ReplicaSet` | Bas niveau (rarement direct) | ❌ | ❌ |
| `StatefulSet` | Stateful (DB, cluster app) | ✅ (nom + volume) | ✅ |
| `DaemonSet` | 1 Pod par node (agents, CNI) | ❌ | ❌ |
| `Job` | Tâche batch qui se termine | ❌ | dépend |
| `CronJob` | Schedule Cron → Jobs | ❌ | — |

### ReplicaSet — orphelinage & adoption (label-driven)

Le lien **contrôleur ↔ Pod** se fait **par `selector` (labels)**, matérialisé par un `ownerReference` sur le Pod. D'où 3 manips examinables :

| Action | Commande / manip | Effet |
|---|---|---|
| **Orphaner** | `kubectl delete rs rs-one --cascade=orphan` | Supprime le RS, **garde les Pods** (non-disruptif). Vaut aussi pour Deployment/StatefulSet. |
| **Adopter** | recréer le RS avec **le même `selector`** | Le nouveau RS **ré-adopte** les Pods orphelins existants (pas de recréation). ⚠️ Ne met **pas** à jour l'image des Pods adoptés. |
| **Isoler** | `kubectl label pod <p> system=IsolatedPod --overwrite` (label ne matchant plus) | Le Pod **sort** du RS → le RS crée un **remplaçant** pour tenir `replicas`. Le Pod isolé survit. |

> **Pattern ops/exam** : pour debugger un Pod fautif sans interruption de service, **change son label** pour le sortir du contrôleur — le RS spawn un Pod sain à sa place, et tu gardes le malade intact pour l'autopsie.

**Options de `--cascade`** : `background` (défaut — supprime le contrôleur, GC supprime les Pods en tâche de fond), `foreground` (supprime les Pods **avant** le contrôleur), `orphan` (garde les Pods).

### Rolling update & rollback (Deployment)

Mettre à jour un `Deployment` (ex. `kubectl set image`) = basculer **progressivement** ses Pods de l'ancien `ReplicaSet` vers un nouveau.

**Deux stratégies** (`spec.strategy.type`) :

| Stratégie | Comportement | Downtime |
|---|---|---|
| **`RollingUpdate`** (défaut) | Crée les nouveaux Pods et supprime les anciens **par vagues** ; les 2 versions coexistent le temps du basculement. | ❌ aucun |
| **`Recreate`** | Supprime **tous** les anciens Pods, **puis** crée les nouveaux. | ⚠️ oui (utile si 2 versions ne peuvent pas tourner ensemble) |

**Deux curseurs qui règlent le rythme du RollingUpdate** (défaut **25 %** chacun ; valeur en % ou en nombre absolu) :

| Champ | Ce qu'il autorise | Réglage |
|---|---|---|
| `maxUnavailable` | Nombre de Pods qui peuvent **manquer** sous le compte désiré pendant la MàJ. | `0` = jamais en dessous du désiré (plus sûr, mais plus lent). |
| `maxSurge` | Nombre de Pods créés **en plus** du désiré, temporairement. | Plus élevé = bascule plus rapide, mais consomme plus de ressources. |

**Historique & rollback** : chaque révision = un `ReplicaSet` **conservé** (l'ancien est mis à `replicas=0`, pas supprimé). D'où le retour arrière en une commande : `kubectl rollout undo deploy/web` (ou `--to-revision=N`, historique via `kubectl rollout history deploy/web`).

```mermaid
sequenceDiagram
    participant U as User
    participant D as Deployment
    participant OldRS
    participant NewRS
    U->>D: kubectl set image
    D->>NewRS: create (replicas=1, +maxSurge)
    D->>OldRS: scale down (-maxUnavailable)
    loop until desired
        D->>NewRS: scale up
        D->>OldRS: scale down
    end
    D->>OldRS: replicas=0 (garde historique)
```

### StatefulSet — spécificités

- Nom des Pods : `web-0`, `web-1`, `web-N` (**ordinal stable**)
- Chaque Pod a son propre PVC (via `volumeClaimTemplates`)
- Nécessite un **Headless Service** (`clusterIP: None`) → DNS `web-0.web.default.svc.cluster.local`
- Ordre de création/suppression garanti (peut être relaxé avec `podManagementPolicy: Parallel`)

### Job / CronJob — spécificités

**Job** — exécute des Pods jusqu'à **succès**, puis s'arrête (pas long-running).

- `completions` : nombre de succès requis pour finir le Job (défaut 1)
- `parallelism` : nombre de Pods en parallèle (défaut 1)
- `backoffLimit` : nombre de retries avant de marquer le Job `Failed` (défaut 6)
- `activeDeadlineSeconds` : coupe le Job après N secondes quoi qu'il arrive (échec `reason: DeadlineExceeded`)
- `ttlSecondsAfterFinished` : supprime auto le Job **et ses Pods** N s après la fin (`Complete` ou `Failed`) ; `0` = immédiat, absent = jamais
- `restartPolicy` **obligatoire** : `Never` ou `OnFailure` (jamais `Always` dans un Job)
- Patterns : `completions=1/parallelism=1` = one-shot ; `completions=N/parallelism=M` = work queue

**CronJob** — crée des Jobs sur un **schedule cron** (`"0 3 * * *"`).

- `concurrencyPolicy` : `Allow` (défaut, chevauchement OK) · `Forbid` (saute si le précédent tourne encore) · `Replace` (tue le précédent)
- `startingDeadlineSeconds` : délai max pour lancer un Job manqué (sinon skip)
- `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` : combien de vieux Jobs garder
- `suspend: true` : met en pause le scheduling

### DaemonSet — spécificités

- **1 Pod par node** (pas de champ `replicas`) ; ajout/suppression auto quand un node rejoint/quitte
- Placement via `nodeSelector` / `tolerations` / affinity ; pour tourner sur le control plane → **tolérer** `node-role.kubernetes.io/control-plane:NoSchedule` (cf. piège [W3](PIEGES-EXAMEN.md))
- `updateStrategy` : `RollingUpdate` (défaut) ou `OnDelete`
  - **RollingUpdate** : `maxUnavailable` (défaut **1**) **et** `maxSurge` (défaut **0**, GA depuis 1.25 — attention : Deployment a `maxSurge` **25 %** par défaut, le DS **0**). MàJ automatique, un node à la fois.
  - **OnDelete** : `set image` / `edit` **ne recrée pas** les Pods existants → l'admin doit `kubectl delete pod` chaque Pod pour que le remplaçant démarre avec la nouvelle image.
- Compatible `kubectl rollout` (status/history/undo) — **même sur OnDelete**, mais `undo`/`set image` ne changent que le **template** ; les Pods ne bougent qu'à leur suppression manuelle.

### Scheduling

**Cycle du kube-scheduler** (watch les Pods sans `nodeName`) :

1. **Filtering** (predicates) : écarte les nodes infaisables (ressources, taint non toléré, `nodeSelector`, `unschedulable`).
2. **Scoring** (priorities) : note les nodes restants → prend le meilleur.
3. **Binding** : écrit un objet `Binding` (= `pod.spec.nodeName`) sur l'API server → le **kubelet** du node crée les conteneurs.

```mermaid
flowchart TD
    P["Pod créé<br/>(spec.nodeName vide)"] --> W[kube-scheduler le watch]
    W --> F["1 · Filtering<br/>écarte les nodes infaisables<br/>(ressources, taints, nodeSelector…)"]
    F --> C{Au moins<br/>1 node faisable ?}
    C -- Non --> PEND["Pod Pending<br/>event FailedScheduling"]
    PEND -.retry.-> F
    C -- Oui --> S["2 · Scoring<br/>note les nodes restants<br/>→ garde le meilleur"]
    S --> B["3 · Binding<br/>écrit spec.nodeName via l'API"]
    B --> K["kubelet du node<br/>crée les conteneurs (CRI)"]
```

- Aucun node faisable → Pod **`Pending`** + event `FailedScheduling` (`kubectl describe pod` / `get events`). Pas d'erreur bloquante, il attend.
- **`spec.schedulerName`** : utilise un scheduler custom au lieu du `default-scheduler` (multiple schedulers en parallèle).
  - ⚠️ Si le scheduler nommé **n'est pas déployé** → Pod `Pending` **sans event `FailedScheduling`** (aucun scheduler ne watch ce Pod). Diagnostic : vérifier `spec.schedulerName` (≠ Pending classique par manque de ressources, qui lui génère `FailedScheduling`).
- **Scheduling profiles** (`KubeSchedulerConfiguration`, via `--config`) : active/désactive des plugins de filtering/scoring et ajuste leurs poids, sans scheduler custom. Sur kubeadm le scheduler est un **static Pod** (`/etc/kubernetes/manifests/kube-scheduler.yaml`). Borderline CKA — connaître le terme suffit.
  - Un plugin se branche sur un **point d'extension** (le cycle du scheduler découpé en slots) : `queueSort` (tri de la file) → `preFilter`/`filter`/`postFilter` (Filtering + préemption) → `preScore`/`score` (Scoring) → `reserve`/`permit`/`preBind`/`bind`/`postBind` (Binding).
  - **Activés par défaut** (les examinables) : `NodeResourcesFit` (ressources), `NodeAffinity` (`nodeSelector`+affinity), `NodeName`, `NodePorts` (`hostPort`), `TaintToleration`, `PodTopologySpread`, `InterPodAffinity`, `VolumeBinding` (PVC), `NodeUnschedulable` (écarte les `cordon`), `ImageLocality` (favorise l'image déjà présente, score), `DefaultPreemption` (postFilter), `PrioritySort` (queueSort). La plupart agissent en `filter` **et** `score`.
  - **Ce qu'un profile permet** : `disabled` (couper un plugin défaut, ex. `ImageLocality`) · `enabled` (ajouter/activer un plugin) · ajuster les **poids** de scoring (`pluginConfig`) · choisir la stratégie de `NodeResourcesFit` — `LeastAllocated` (défaut = étale) vs `MostAllocated` (bin-packing) · définir **plusieurs profiles** dans un seul binaire, chacun avec son `schedulerName` (un Pod le choisit via `spec.schedulerName`, sans déployer de 2ᵉ scheduler).

| Mécanisme | Sens | Portée |
|---|---|---|
| `nodeSelector` | Pod → Node (labels exacts) | Simple |
| `affinity.nodeAffinity` | Pod → Node (règles complexes, soft/hard) | Riche |
| `affinity.podAffinity/AntiAffinity` | Pod → Pod (co-localisation ou séparation) | Topology |
| `tolerations` + `taints` | Node repousse les Pods sauf tolérants | Réservation |
| `topologySpreadConstraints` | Répartition entre zones/hosts | HA |
| `priorityClassName` | Ordre de scheduling, préemption | Multi-workload |

> 💡 **`topologySpreadConstraints` = successeur de `podAntiAffinity` pour le *spread* (HA) uniquement**, pas un remplacement total :
> - `podAntiAffinity` est **binaire** (« 0/1 Pod par topologie ») et **coûteux** (O(Pods²), ralentit le scheduler à grande échelle).
> - `topologySpreadConstraints` exprime un **déséquilibre chiffré** via `maxSkew` (ex. « ~2 Pods/zone, écart ≤ 1 »), avec `whenUnsatisfiable: DoNotSchedule` (hard) ou `ScheduleAnyway` (soft) — plus léger.
> - Mais `podAffinity`/`podAntiAffinity` restent **irremplaçables** pour **co-localiser** (rapprocher un Pod d'un autre) ou une **exclusion dure Pod↔Pod** (« jamais 2 replicas DB sur le même node »). Le spread ne fait que **répartir**, jamais rapprocher.

**Structure d'un taint** — posé **sur le node**, format `key=value:effect` (la `value` est **optionnelle** → `key:effect` ou `key=:effect` valides) :

```bash
kubectl taint node n1 gpu=true:NoSchedule    # key=gpu, value=true, effect=NoSchedule
kubectl taint node n1 gpu:NoSchedule         # value vide (matché par operator: Exists)
kubectl taint node n1 gpu=true:NoSchedule-   # le "-" final RETIRE le taint
```

Le **node repousse** le Pod via son taint ; le Pod n'est **admis que s'il porte une `toleration`** correspondante (posée **sur le Pod**). Une toleration matche un taint via 2 opérateurs :

| Champ toleration | Rôle |
|---|---|
| `key` | doit correspondre à la `key` du taint (vide + `Exists` = matche **tout** taint) |
| `operator` | `Equal` (défaut → compare aussi la `value`) · `Exists` (ignore la `value`, matche la seule présence de la clé) |
| `value` | comparée **uniquement** si `operator: Equal` |
| `effect` | l'effet toléré (vide = tolère **tous** les effets de cette clé) |

```yaml
tolerations:
- key: gpu
  operator: Equal        # matche si key=gpu ET value=true
  value: "true"
  effect: NoSchedule
```

> 🔑 **Taint (node) et toleration (Pod) sont les 2 moitiés d'un même mécanisme** : le taint *repousse*, la toleration *autorise*. Une toleration ne **force** jamais le placement (contrairement à l'affinity) — elle **lève seulement** le blocage. Un Pod tolérant peut donc atterrir ailleurs.

**Taints — 3 effets** (le champ `effect`) :
- `NoSchedule` : refuse nouveaux Pods
- `PreferNoSchedule` : évite si possible
- `NoExecute` : évince les Pods existants
  - **`tolerationSeconds`** (seulement avec `NoExecute`) : le Pod toléré reste N secondes avant éviction (sans = immédiat).
- **Taint-based evictions** : le node-controller pose auto des taints `NoExecute` sur node malade (`node.kubernetes.io/not-ready`, `unreachable`, `disk-pressure`…) ; K8s injecte une toleration **300 s** par défaut → délai avant reschedule quand un node tombe. ⚠️ Ces évictions **ne respectent pas les PodDisruptionBudgets** (contrairement à `drain`).

Exemple : les control plane ont par défaut `node-role.kubernetes.io/control-plane:NoSchedule`.

**Affinity (node / pod) — `required` vs `preferred`** — ces 2 modes sont des sous-champs de `spec.affinity` (`nodeAffinity`, `podAffinity`, `podAntiAffinity`), **pas** des tolerations (une toleration se contente de matcher ou non un taint, sans mode hard/soft) :
- `requiredDuringSchedulingIgnoredDuringExecution` = **hard** : obligatoire au scheduling, sinon Pod **`Pending`** (garantie).
- `preferredDuringSchedulingIgnoredDuringExecution` = **soft** : simple préférence (scoring), planifie ailleurs si besoin.
- `IgnoredDuringExecution` = évalué **au scheduling seulement** → changer les labels du node **après** ne réévince pas le Pod.

> ⚠️ Ne pas confondre : l'**affinity attire/repousse activement** (le Pod *choisit* et peut **forcer** son node via `required`) ; la **toleration** ne fait que *lever* un blocage de taint (elle n'attire ni ne force jamais un placement).

> 💡 Question piège : un Pod sans `tolerations` peut être planifié sur un node **cordoned** ? **Non** — `cordon` = `unschedulable=true`, complètement différent des taints.

> 🔑 **K8s ne rééquilibre jamais les Pods déjà planifiés.** Le scheduler n'agit qu'à la **création** : un Pod reste sur son node jusqu'à sa suppression, même si un meilleur node se libère (ex. retirer un taint `NoExecute` ne ramène pas les Pods évincés ; scale-up de nodes ne migre pas les Pods existants). Rééquilibrage = projet **`descheduler`** (opt-in, pas natif).

### Requests, limits, QoS

`requests`/`limits` se **déclarent par conteneur** (`spec.containers[].resources`), mais agissent à des niveaux différents :

| Notion | Où on l'écrit | À quel niveau ça agit |
|---|---|---|
| `requests` | conteneur | **scheduling** : le scheduler **somme** les requests des conteneurs → choisit un node (réservation). |
| `limits` | conteneur | **runtime, par conteneur** : CPU throttle · mémoire dépassée → **OOMKill de ce conteneur**. |
| **classe QoS** | dérivée (non écrite) | **Pod entier** : étiquette calculée auto → **ordre d'éviction** sous pression mémoire du node. |

- `requests` = garantie de réservation (scheduling)
- `limits` = plafond (CPU throttle, mémoire → OOMKill)
- **Classes QoS (Quality of Service)** = une **étiquette que K8s colle à chaque Pod**, déduite de la façon dont ses conteneurs déclarent `requests`/`limits`. Tu ne l'écris pas : elle est **calculée automatiquement** et lisible dans `status.qosClass`. Elle sert **une seule chose** — décider **quels Pods sont tués en premier** quand un node manque de mémoire (`MemoryPressure`).

| Classe | Condition (comment on l'obtient) |
|---|---|
| `Guaranteed` | `requests == limits` **définis** pour **tous** les conteneurs, en CPU **et** mémoire (le plus protégé) |
| `Burstable` | au moins un conteneur a des `requests` < `limits` (ou requests sans limits) |
| `BestEffort` | **aucun** conteneur ne déclare ni `requests` ni `limits` (le plus sacrifiable) |

**Priorité d'éviction** (qui meurt d'abord sous pression mémoire) : `BestEffort` > `Burstable` > `Guaranteed`.

> 💡 **Unités (case-sensitive !)** :
> - **CPU** : `1` = 1 cœur ; `500m` = 0,5 cœur (m = **milli**cpu). `0.5` == `500m`.
> - **Mémoire** : suffixes **binaires** `Ki`/`Mi`/`Gi` (1024) ou **décimaux** `K`/`M`/`G` (1000). `Mi` ≠ `mi` ≠ `M`.
> - Piège classique : `150mi` ou `256mb` → **rejeté/panic** (`unable to parse quantity's suffix`). La bonne forme = `150Mi`, `256Mi`.
> - Attention : `m` minuscule sur la **mémoire** = **milli-octets** (`500m` = 0,5 octet !) → jamais ce qu'on veut.
### securityContext (Pod & container)

Contrôle **qui/comment** tourne le process. Niveau **Pod** (`spec.securityContext`, s'applique à tous les containers) ou **container** (`spec.containers[].securityContext`, prioritaire).

| Champ | Effet |
|---|---|
| `runAsUser` / `runAsGroup` | UID/GID du process (ex. `runAsUser: 101` = user nginx) |
| `runAsNonRoot: true` | refuse le démarrage si l'image tourne en root → `CreateContainerConfigError` |
| `fsGroup` | GID propriétaire des volumes montés (fixe les perms d'écriture) |
| `allowPrivilegeEscalation: false` | bloque setuid/sudo dans le container |
| `readOnlyRootFilesystem: true` | FS racine en lecture seule |
| `capabilities` | `add`/`drop` de capabilities Linux (ex. `drop: ["ALL"]`) |

> 💡 Piège type ([Domain Review #34](DOMAIN-REVIEW-CHECKLIST.md)) : un Pod crashe car nginx ne peut pas lire sa conf → `runAsUser: <uid nginx>`. `runAsNonRoot: true` **sans** `runAsUser` sur une image root = refus de démarrage.

### ResourceQuota & LimitRange (par namespace)

| Objet | Portée | Rôle |
|---|---|---|
| **ResourceQuota** | namespace | Plafond **global** du namespace : total CPU/mémoire, et **compte d'objets** (Pods, Services, PVC, Secrets…). Multi-tenant. |
| **LimitRange** | namespace | Valeurs **par conteneur/Pod** : `default`, `defaultRequest`, min, max. Injecte des requests/limits si le Pod n'en déclare pas. |

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-quota, namespace: dev }
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    persistentvolumeclaims: "5"
```

> ⚠️ **Piège** : si un `ResourceQuota` fixe `requests.cpu`/`limits.memory` sur le namespace, **tout** Pod créé **doit** déclarer les requests/limits correspondantes, sinon il est **refusé** (`forbidden: failed quota`). C'est là que `LimitRange` (valeurs par défaut) devient utile. (cf. piège [W9](PIEGES-EXAMEN.md))
> 💡 `scopeSelector` : un quota peut ne s'appliquer qu'à certains Pods (ex: un `priorityClassName` donné) → politiques différenciées par priorité.
> Vérifier : `kubectl describe quota -n <ns>` (montre `Used / Hard`).

#### LimitRange — notes pratiques

Un `LimitRange` agit **par conteneur (ou par Pod/PVC)** au moment de l'admission. 5 leviers, **tous optionnels** :

| Champ | Effet | Obligatoire ? (défaut) |
|---|---|---|
| `type` | cible de l'entrée : `Container` · `Pod` · `PersistentVolumeClaim` | ✅ **seul champ requis** de l'entrée |
| `defaultRequest` | `requests` **injectées** si le conteneur n'en déclare pas | ❌ optionnel — si absent mais `default` posé → **prend la valeur de `default`** |
| `default` | `limits` **injectées** si le conteneur n'en déclare pas | ❌ optionnel — rien d'injecté si absent (`Container` uniquement) |
| `min` | valeur **plancher** — un conteneur qui demande moins est **refusé** | ❌ optionnel |
| `max` | valeur **plafond** — un conteneur qui demande plus est **refusé** | ❌ optionnel |
| `maxLimitRequestRatio` | borne le ratio `limits/requests` (empêche un overcommit trop agressif) | ❌ optionnel |

> 💡 Aucune contrainte n'est obligatoire : un `LimitRange` avec juste `max` est valide. Seul `type` l'est. `default`/`defaultRequest` n'agissent que sur `type: Container` (pas d'injection de défauts pour `Pod`/`PVC`). Cohérence exigée : `min ≤ defaultRequest ≤ default ≤ max`.

```yaml
apiVersion: v1
kind: LimitRange
metadata: { name: defaults, namespace: dev }
spec:
  limits:
  - type: Container            # ou Pod, ou PersistentVolumeClaim
    defaultRequest: { cpu: 100m, memory: 128Mi }   # si non déclaré
    default:        { cpu: 500m, memory: 256Mi }   # si non déclaré
    min:            { cpu: 50m,  memory: 64Mi }    # plancher (refus si <)
    max:            { cpu: "2",  memory: 1Gi }     # plafond (refus si >)
    maxLimitRequestRatio: { cpu: 4 }               # limits ≤ 4× requests
  - type: PersistentVolumeClaim
    min: { storage: 1Gi }
    max: { storage: 10Gi }
```

Notes pour tes projets :
- Un LimitRange **ne modifie pas** les Pods existants — il ne s'applique qu'aux **créations/mises à jour** après sa pose.
- **Ordre d'application** : le LimitRange injecte d'abord les defaults, **puis** le ResourceQuota valide le cumul. Les deux ensemble = un namespace « discipliné » sans avoir à écrire les resources dans chaque manifest.
- Pas de `kubectl create limitrange` → **YAML obligatoire** (`kubectl apply -f`).
- `type: Pod` borne la **somme** des conteneurs du Pod ; `type: Container` borne **chaque** conteneur.

**Voir / mettre à jour** (pas de commande impérative → tout via l'API objet) :

```bash
# --- Voir ---
kubectl get limitrange -n dev
kubectl describe limitrange defaults -n dev    # ⭐ tableau Min/Max/Default/DefaultRequest/Ratio par ressource
kubectl get limitrange defaults -n dev -o yaml # manifest complet

# --- Mettre à jour (3 voies) ---
kubectl apply -f limitrange.yaml               # ré-appliquer le YAML (idempotent, GitOps)
kubectl edit limitrange defaults -n dev        # édition à chaud ($EDITOR sur l'objet live)
kubectl patch limitrange defaults -n dev --type merge \
  -p '{"spec":{"limits":[{"type":"Container","default":{"cpu":"1"}}]}}'   # patch ciblé
```

> ⚠️ Modifier un `LimitRange` **ne retouche pas** les Pods déjà créés — les nouvelles valeurs ne valent que pour les **créations/updates suivants**. Pour rattraper l'existant → `kubectl rollout restart` (recrée les Pods). Idem `ResourceQuota` : `kubectl get/describe/edit quota -n dev` (le `describe` montre `Used / Hard`).

#### PriorityClass + scopeSelector (culture)

Pour **différencier les budgets par priorité** dans un même namespace : une `PriorityClass` + un `ResourceQuota` ciblé via `scopeSelector`.

```yaml
# 1. Définir les priorités (objet cluster-scoped)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: high }
value: 100000
# globalDefault: true   # ← option : appliquée à tout Pod SANS priorityClassName (un seul autorisé)
---
# 2. Quota qui ne cible QUE les Pods high
apiVersion: v1
kind: ResourceQuota
metadata: { name: quota-high, namespace: prod }
spec:
  hard: { requests.cpu: "20", requests.memory: 40Gi, pods: "50" }
  scopeSelector:
    matchExpressions:
    - { operator: In, scopeName: PriorityClass, values: ["high"] }
```

```yaml
# 3. Affecter la classe au Pod (dans template.spec pour un controller)
spec:
  priorityClassName: high        # → K8s calcule spec.priority = 100000
  containers: [ ... ]
```

Notes :
- **Affectation** : champ `spec.priorityClassName` (Pod) ou `template.spec.priorityClassName` (Deployment/STS/DS). Valeur numérique calculée dans `spec.priority` (lecture seule).
- Sans classe ni `globalDefault` → priorité **0**.
- **Scopes `scopeSelector`** : `PriorityClass` (seul à accepter `values`), `BestEffort`, `NotBestEffort`, `Terminating`, `NotTerminating`, `CrossNamespacePodAffinity`.
- ⚠️ Un Pod **sans** priorityClassName n'est matché par **aucun** quota ciblé `In [high|low]` → prévoir un quota catch-all, ou imposer la classe (Kyverno/OPA).
- `priorityClassName` sert **aussi** au scheduler (ordre + **préemption** des Pods moins prioritaires).

### HPA (Horizontal Pod Autoscaler)

- `autoscaling/v2` : multiple metrics (CPU, mem, custom, external)
- Cible un **Deployment, ReplicaSet ou StatefulSet** — jamais un Pod nu ni un DaemonSet
- Requiert **metrics-server** (métriques CPU/mém via `metrics.k8s.io`) ou un adapter (Prometheus) pour custom/external
- ⭐ **Même source que `kubectl top`** : si `kubectl top pods` marche, le HPA a ses métriques. Sinon → colonne `TARGETS` affiche `<unknown>` et **aucun scaling**
- ⭐ **% calculé sur les `requests`, jamais les `limits`** : `TARGETS = usage / requests.cpu`. Ex. `requests.cpu=5m` + usage `10m` → **200 %**
- ⚠️ **`<unknown>` a 2 causes distinctes, même affichage** :
  - **metrics-server absent** → pas d'**usage** (le numérateur manque) ; `kubectl top pods` échoue aussi.
  - **pas de `requests.cpu` sur le conteneur** → pas de **base de calcul** (le dénominateur manque, car `%  = usage / requests.cpu`) ; `kubectl top pods` **marche** pourtant.
  - → réflexe diagnostic : si `top` fonctionne mais le HPA reste `<unknown>`, c'est le `requests.cpu` qui manque. Toujours définir un CPU request sur la cible d'un HPA `Utilization`.
- Poll du controller **toutes les 15 s** (`--horizontal-pod-autoscaler-sync-period`)
- **Scale-up immédiat**, **scale-down temporisé 300 s** (`--horizontal-pod-autoscaler-downscale-stabilization`, défaut 5 min) → évite le *flapping*
- Ne fonctionne **pas** avec `replicas` figées si `Deployment.spec.replicas` est défini par un contrôleur externe (GitOps)

### Manifest management

- **Helm** : templating + release management (versions, rollback, values). Chart = tarball.
- **Kustomize** (`kubectl apply -k`) : overlays, patches, no templating. Natif dans `kubectl`.
- Choix pratique : **Kustomize** pour env-specific + **Helm** pour packaging tiers.

**Structure Kustomize** — base + overlays, tout piloté par des fichiers `kustomization.yaml` :

```
base/
├── kustomization.yaml      # resources: [deployment.yaml, service.yaml]
├── deployment.yaml
└── service.yaml
overlays/prod/
└── kustomization.yaml      # references ../../base + patches spécifiques prod
```

`kustomization.yaml` (overlay) — champs les plus courants :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base                 # hérite de la base
namespace: prod                # force le ns de toutes les ressources
namePrefix: prod-              # préfixe tous les noms
commonLabels: { env: prod }    # labels ajoutés partout  (déprécié → voir labels: ci-dessous)
labels:                        # forme moderne qui remplace commonLabels
  - pairs: { env: prod }
    includeSelectors: false    # false (défaut) = labels sur metadata seulement ; true = aussi dans le selector (immuable → risque sur ressource existante)
images:
  - name: nginx               # override le tag d'image sans toucher au YAML de base
    newTag: 1.27-alpine
replicas:
  - name: web
    count: 5
patches:                       # strategic merge OU JSON patch (RFC 6902)
  - path: patch-resources.yaml
configMapGenerator:            # génère un ConfigMap + hash suffix (rollout auto au changement)
  - name: app-config
    literals: [LOG_LEVEL=debug]
```

- **2 types de patch** : *strategic merge* (fusionne un fragment YAML) ou *JSON patch* (`op: replace/add/remove` sur un chemin).
- `kubectl kustomize <dir>` = **rend** le YAML final (dry-run, rien d'appliqué) ; `kubectl apply -k <dir>` = **applique**.
- `configMapGenerator`/`secretGenerator` ajoutent un **hash** au nom → tout changement force un **rolling update** du Deployment qui les monte.
- ⚠️ **`commonLabels` (ancien) injecte le label dans le `selector` du Deployment** — or `spec.selector` est **immuable** après création. Donc `apply -k` sur un Deployment **déjà déployé** échoue (`field is immutable`). La forme moderne `labels:` corrige ça : `includeSelectors: false` **par défaut** → le label va sur `metadata` + template **mais pas** dans le selector, donc sûr même sur ressource existante (détails + rendu comparé plus bas).
- ⚙️ *Exam CKA = niveau basique* : comprendre base/overlay, `-k`, `kubectl kustomize`, override image/replicas. Les generators + hash = bonus compréhension.

**Exemple concret — ce que `includeSelectors` change au rendu.**

Base `deployment.yaml` + `kustomization.yaml` :

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  selector:
    matchLabels: { app: web }        # selector d'origine
  template:
    metadata:
      labels: { app: web }
    spec:
      containers: [{ name: web, image: nginx }]
---
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml]
labels:
  - pairs: { env: prod }
    includeSelectors: false          # ← on teste false vs true
```

`kubectl kustomize .` avec **`includeSelectors: false`** (défaut) — le label `env: prod` va sur `metadata` et le template, **PAS** dans le selector :

```yaml
metadata:
  labels: { app: web, env: prod }    # ✅ ajouté ici
spec:
  selector:
    matchLabels: { app: web }        # ✅ inchangé → apply -k sûr même sur ressource existante
  template:
    metadata:
      labels: { app: web, env: prod }
```

Avec **`includeSelectors: true`** — `env: prod` est aussi injecté dans le selector :

```yaml
spec:
  selector:
    matchLabels: { app: web, env: prod }   # ⚠️ selector modifié
```

Si le Deployment `web` **existe déjà** avec l'ancien selector (`app: web` seul), `kubectl apply -k .` échoue :

```
The Deployment "web" is invalid: spec.selector: Invalid value: ...:
field is immutable
```

→ Règle : `includeSelectors: true` (et `commonLabels`) **uniquement à la création**. Sur une ressource déjà déployée, garde `false`.

**Exemple concret — `configMapGenerator` + hash (rollout automatique).**

```yaml
# kustomization.yaml
configMapGenerator:
  - name: app-config
    literals: [LOG_LEVEL=debug]
```

`kubectl kustomize .` génère un ConfigMap dont le **nom porte un hash** du contenu :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-9f8b7c6d5e     # ← suffixe = hash du contenu
data: { LOG_LEVEL: debug }
```

Et toute référence à ce ConfigMap est **réécrite avec le même hash** :

```yaml
        envFrom:
          - configMapRef: { name: app-config-9f8b7c6d5e }
```

→ Change `LOG_LEVEL=info` ⇒ nouveau hash `app-config-1a2b3c...` ⇒ le Deployment voit un **nouveau nom** dans son template ⇒ **rolling update automatique**. Sans le generator, éditer un ConfigMap classique ne redémarre **pas** les Pods (ils gardent l'ancienne valeur montée). C'est l'intérêt principal du generator.

**Exemple concret — 2 styles de `patches`.**

*Strategic merge* (tu écris un fragment YAML, Kustomize le fusionne par `name`) :

```yaml
# kustomization.yaml
patches:
  - path: bump-replicas.yaml
# bump-replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec: { replicas: 5 }        # seul ce champ est fusionné
```

*JSON patch RFC 6902* (opérations explicites sur un chemin) :

```yaml
patches:
  - target: { kind: Deployment, name: web }
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value: { name: TIER, value: backend }
```

→ *strategic merge* = lisible, pratique pour modifier/ajouter des champs. *JSON 6902* = précis, seul moyen fiable pour **supprimer** (`op: remove`) ou viser un **index de liste** exact.

## 📋 Commandes essentielles

```bash
# --- Génération de manifests ---
kubectl create deploy web --image=nginx --replicas=3 $do > deploy.yaml
kubectl run p --image=nginx --restart=Never $do > pod.yaml         # Pod nu
kubectl run p --image=nginx --restart=Never --command -- sleep 3600
kubectl create job onetime --image=busybox -- echo hello
kubectl create cronjob backup --schedule="0 3 * * *" --image=busybox -- /backup.sh

# --- Rollouts ---
kubectl rollout status deploy/web
kubectl rollout history deploy/web
kubectl rollout history deploy/web --revision=3
kubectl rollout undo deploy/web
kubectl rollout undo deploy/web --to-revision=2
kubectl rollout pause deploy/web ; kubectl rollout resume deploy/web
kubectl set image deploy/web c=nginx:1.25 --record        # --record deprecated 1.25+
kubectl scale deploy/web --replicas=5
kubectl autoscale deploy/web --min=2 --max=10 --cpu=70%        # moderne, accepte "70%" ; --cpu-percent=70 (entier) marche aussi

# --- Scheduling ---
kubectl label node n1 disk=ssd
kubectl taint node n1 key=val:NoSchedule
kubectl taint node n1 key-                                # retire
kubectl cordon n1 ; kubectl uncordon n1
kubectl drain n1 --ignore-daemonsets --delete-emptydir-data --force

# --- Kustomize ---
kubectl apply -k overlays/prod/
kubectl kustomize overlays/prod/                          # rend sans appliquer

# --- Ressources / QoS ---
kubectl top pod --all-namespaces --sort-by=memory
kubectl get pod <name> -o jsonpath='{.status.qosClass}'
```

## 📄 YAML de référence

```yaml
# Deployment avec probes et resources (bonne pratique)
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, labels: { app: web } }
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 1, maxSurge: 1 }
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - name: c
        image: nginx:1.25
        ports: [{ containerPort: 80 }]
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits:   { cpu: 500m, memory: 256Mi }
        readinessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 3
        livenessProbe:
          httpGet: { path: /, port: 80 }
          initialDelaySeconds: 10
```

```yaml
# DaemonSet — agent sur tous les nodes (y compris CP grâce à tolerations)
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent, namespace: kube-system }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
      - operator: Exists                       # tolère TOUS les taints
      hostNetwork: true                        # accès direct réseau host
      containers:
      - { name: agent, image: myrepo/agent:1.0 }
```

```yaml
# StatefulSet + Headless Service
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  clusterIP: None                              # headless
  selector: { app: web }
  ports: [{ port: 80 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web
  replicas: 3
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - name: c
        image: nginx:1.25
        volumeMounts: [{ name: data, mountPath: /usr/share/nginx/html }]
  volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      accessModes: [ReadWriteOnce]
      resources: { requests: { storage: 1Gi } }
      storageClassName: standard
```

```yaml
# Pod avec affinity + tolerations + topologySpread
apiVersion: v1
kind: Pod
metadata: { name: sched, labels: { app: web } }
spec:
  tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: NoSchedule
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - { key: disk, operator: In, values: [ssd] }
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector: { matchLabels: { app: web } }
          topologyKey: kubernetes.io/hostname   # 1 Pod max par node
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector: { matchLabels: { app: web } }
  containers: [{ name: c, image: nginx }]
```

> 🔑 **Les 4 formes d'affinity ont des champs imbriqués différents** (piège à la rédaction — la doc `kubernetes.io` est autorisée à l'exam) :
>
> | Forme | Champ imbriqué | `topologyKey` |
> |---|---|---|
> | `nodeAffinity` **required** | `nodeSelectorTerms:` → `matchExpressions` | ❌ |
> | `nodeAffinity` **preferred** | `preference:` → `matchExpressions` (+ `weight`) | ❌ |
> | `podAffinity`/`podAntiAffinity` **required** | `labelSelector:` (+ `topologyKey`) | ✅ obligatoire |
> | `podAffinity`/`podAntiAffinity` **preferred** | `podAffinityTerm:` → `{labelSelector, topologyKey}` (+ `weight`) | ✅ obligatoire |
>
> `weight` (1–100) existe **uniquement** en `preferred`. `required` est binaire (pas de weight).

```yaml
# HPA v2 (CPU + custom metric)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```

## ⚠️ Pièges fréquents

### Deployments
- `strategy: Recreate` = **downtime**. Ne pas confondre avec un rolling update.
- `spec.selector` **immutable** après création. Modifier = recréer le Deployment.
- `--record` (rolling updates) : **deprecated depuis 1.15**, absent des exemples officiels 2024+. Ne pas l'utiliser à l'exam CKA. Alternatives :
  - `kubectl annotate deploy/web kubernetes.io/change-cause="upgrade nginx 1.26" --overwrite`
  - Ou baker l'annotation directement dans le manifest
  > 💡 `kubernetes.io/change-cause` = annotation **standard réservée** (préfixe `kubernetes.io/`/`k8s.io/` réservé au core), **lue par `kubectl`** → alimente la colonne `CHANGE-CAUSE` de `rollout history`. Nom + sémantique fixes ; ne pas inventer d'autres clés sous ce préfixe (utiliser `ton-domaine.com/...`).
  > ⚠️ L'ancien cours LFS158 le présente encore comme "valuable" → **contenu daté**.

### StatefulSet
- Supprimer un StatefulSet **ne supprime pas** les PVC (par défaut). Cleanup manuel : `k delete pvc -l app=web`.
- Scale-down d'un StatefulSet supprime les Pods dans l'ordre inverse (ordinal max → 0).

### DaemonSet
- Oublier les tolerations control-plane → l'agent ne tourne pas sur les CP.
- `updateStrategy: OnDelete` = les Pods ne sont pas recréés à changement d'image, l'admin doit les delete.

### Scheduling
- `nodeName` (champ direct dans `spec`) **bypass** le scheduler → pas de préemption, pas de validation.
- `podAntiAffinity` avec `requiredDuringScheduling` sur un cluster mono-node → Pods `Pending` en permanence.
- Un node peut être `NotReady` **et pourtant** avoir des Pods qui tournent (le scheduler ne crée juste plus de nouveaux Pods).

### Resources
- Pas de `requests` → scheduler considère 0 → **overcommit**, OOMKill silencieux.
- `limits.cpu` **throttle** mais ne kill pas ; `limits.memory` dépassée = **OOMKilled** (137).

## 🔗 Docs officielles autorisées

- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Jobs / CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints & Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [HPA walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [Resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
