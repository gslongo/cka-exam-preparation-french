# ⚠️ Pièges classiques de l'examen CKA

> Fichier vivant — l'agent enrichit au fil de la session.
> Compilation des erreurs qui **coûtent des points** : pièges techniques, réflexes oubliés, et retours récurrents de candidats (forums, killer.sh, Reddit r/kubernetes, blogs de certifiés).
> ⚠️ Basé sur des retours communautaires + curriculum v1.35. Les détails de l'interface évoluent — revérifie les règles officielles le jour J.

_Dernière mise à jour : 2026-07-31_

---

## 🎯 Méta / gestion de l'examen (les plus coûteux)

| # | Piège | Le réflexe qui sauve |
|---|---|---|
| M1 | **Oublier de changer de contexte** entre les tâches | **TOUJOURS** copier-coller le `kubectl config use-context <ctx>` fourni en tête de CHAQUE tâche. Erreur n°1 rapportée : bonne réponse… sur le mauvais cluster = 0 point. |
| M2 | **Rester bloqué** trop longtemps sur une tâche | Time-box : si > 6-8 min sans progrès → **flag + skip**. 66 % suffit, ne coule pas sur une tâche à 4 %. |
| M3 | Ne pas lire le **poids (%)** de la tâche | Fais d'abord les grosses (7-13 %) et les quick wins. Le % est affiché. |
| M4 | Ne pas **vérifier son travail** | Après chaque tâche : `kubectl get`/`describe` pour confirmer que l'objet est dans l'état attendu. |
| M5 | Recopier les chemins/noms **à la main** | Copie-colle noms de fichiers, chemins, noms d'objets depuis l'énoncé → évite les typos silencieuses. |
| M6 | Oublier les **notes/onglets autorisés** | Doc autorisée : `kubernetes.io/docs`, `/blog`, GitHub k8s. **Un seul onglet** de doc en plus du terminal. Prépare tes bookmarks mentaux. |
| M7 | Paniquer sur une tâche « impossible » | Souvent un pré-requis manque (node cordoné, service sans endpoints). Lis les **events**. |

---

## 🏗️ Cluster Architecture / Install (domaine 01 — 25 %)

| # | Piège | Détail |
|---|---|---|
| A1 | **Upgrade : drainer AVANT `apply`** ❌ | Ordre officiel : `install kubeadm → plan → apply → DRAIN → kubelet/kubectl → uncordon`. Le drain vient **après** `upgrade apply`. |
| A2 | `kubeadm upgrade apply` sur un **worker** | Sur worker / CP secondaire → `kubeadm upgrade node` (pas `apply`, pas `plan`). |
| A3 | Lancer `kubeadm join` sur le **control plane** | Le `join` s'exécute **sur le worker**. |
| A4 | **Token expiré** (24 h) et ne pas savoir le régénérer | `kubeadm token create --print-join-command` (régénère token + hash d'un coup). |
| A5 | etcd : oublier les **3 certs** dans etcdctl | Sans `--cacert/--cert/--key` → `context deadline exceeded`. Les chemins sont dans `/etc/kubernetes/manifests/etcd.yaml`. |
| A6 | etcd restore : oublier de **repointer le manifest** | Après `snapshot restore --data-dir=/x`, éditer `etcd.yaml` → `hostPath` vers le nouveau data-dir. |
| A7 | `ETCDCTL_API` — piège de version | etcd **≤ 3.5** : préfixer `ETCDCTL_API=3` (sinon API v2 par défaut sur vieilles images). etcd **3.6 (CKA v1.35)** : API v2 **supprimée**, v3 par défaut → `ETCDCTL_API` **inutile/déprécié**. Syntaxe exam : flags direct sur `exec` (`--cacert/--cert/--key/--endpoints`), sans `sh -c`. **Connaître les 2 formes** (cf. bloc sous le tableau) car killer.sh peut tomber sur un cluster plus vieux. |
| A8 | Éditer un **static pod** avec `kubectl edit` | Impossible. On édite le **fichier** dans `/etc/kubernetes/manifests/`. Le kubelet recrée le Pod. |
| A9 | `kubectl` KO = « cluster mort » | Non : l'apiserver est un static pod. Descends au runtime → `sudo crictl ps -a` + `crictl logs`. |
| A10 | Skew de version | Une seule minor à la fois (1.34→1.35, jamais 1.34→1.36). kubelet ≤ apiserver. |

> **Les deux formes etcdctl à connaître** _(source : LFS258 — l'ancien lab 02-12 utilise la forme env-var, le récent 06-03 la forme flags directs)_ :
>
> ```bash
> # Forme MODERNE (etcd 3.6 / CKA v1.35) — flags directs, pas de sh -c, pas d'ETCDCTL_API
> kubectl -n kube-system exec -it etcd-cp -- etcdctl \
>   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
>   --cert=/etc/kubernetes/pki/etcd/server.crt \
>   --key=/etc/kubernetes/pki/etcd/server.key \
>   --endpoints=https://127.0.0.1:2379 \
>   endpoint health          # ou: member list -w table  |  snapshot save /var/lib/etcd/snapshot.db
>
> # Forme LEGACY (etcd ≤ 3.5) — env vars dans un sh -c
> kubectl -n kube-system exec -it etcd-cp -- sh -c "ETCDCTL_API=3 \
>   ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
>   ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \
>   ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
>   etcdctl --endpoints=https://127.0.0.1:2379 endpoint health"
> ```

---

## 🔐 APIs & Access / Security (domaine 01)

| # | Piège | Détail |
|---|---|---|
| S1 | Confondre `Role` et `ClusterRole` | `Role`/`RoleBinding` = **namespace**. `ClusterRole`/`ClusterRoleBinding` = **cluster-wide**. Piège : un ClusterRole peut être lié par un **RoleBinding** (droits limités à 1 ns). |
| S2 | Mauvais **sujet** de SA | Format exact : `system:serviceaccount:<ns>:<name>`. |
| S3 | Ne pas **vérifier** les droits | `kubectl auth can-i <verb> <res> --as=<user>` (ou `--as=system:serviceaccount:...`). |
| S4 | Oublier que le verbe/ressource est **pluriel/exact** | `--resource=pods` (pas `pod`), verbes : `get,list,watch,create,update,patch,delete`. |
| S5 | CSR : oublier d'**approuver** | `kubectl certificate approve <csr>` — sinon reste `Pending`, cert jamais émis. |

---

## 📦 Workloads & Scheduling (domaine 02 — 15 %)

| # | Piège | Détail |
|---|---|---|
| W1 | Modifier un **champ immuable** d'un Pod avec `apply` | Erreur `field is immutable` → `kubectl replace -f f.yaml --force` (delete+recreate). |
| W2 | Confondre **taint** et **toleration** | Taint = sur le **node** (repousse). Toleration = sur le **Pod** (laisse passer, **n'attire pas**). Pour forcer un placement → `nodeSelector`/affinity **en plus**. |
| W3 | Oublier de **tolérer le taint du control plane** pour un DaemonSet global | `node-role.kubernetes.io/control-plane:NoSchedule`. |
| W4 | `kubectl run` crée un **Pod**, pas un Deployment | Depuis 1.18, `run` = Pod nu. Pour un Deployment → `kubectl create deployment`. |
| W5 | Générer du YAML sans `--dry-run=client` | `k create ... --dry-run=client -o yaml > f.yaml` puis éditer. Gagne un temps fou. |
| W6 | `rollout undo` sur mauvaise ressource | `kubectl rollout undo deployment/<x>` (+ `--to-revision=N`). Vérifie avec `rollout history`. |
| W7 | Oublier `--record` ou l'historique | `--record` est déprécié ; utilise `rollout history` + `kubernetes.io/change-cause` via annotation. |
| W8 | Sidecar : vouloir éditer un Pod existant | On ne rajoute pas un conteneur à chaud → recréer le Pod. |
| W9 | Pod **refusé** dans un namespace avec `ResourceQuota` | Si le quota fixe `requests`/`limits`, tout Pod **doit** les déclarer sinon `forbidden: failed quota`. Ajoute-les au Pod (ou pose un `LimitRange` avec des défauts). Vérifie : `kubectl describe quota -n <ns>`. |
| W10 | Changer le **`selector` d'un Deployment** | `spec.selector.matchLabels` est **immuable** → `apply` échoue (`field is immutable`). Il faut **supprimer et recréer** le Deployment. |
| W11 | `selector` qui ne **matche pas** `template.labels` | À la création : `selector does not match template labels`. Le `selector` doit être un **sous-ensemble** des labels du `template`. Piège #1 en écrivant un Deployment à la main. |
| W12 | `imagePullPolicy` par défaut dépend du **tag** | Tag fixe (`nginx:1.25`) → `IfNotPresent`. Tag `:latest` ou **absent** → `Always` (re-pull à chaque fois). Surprise en debug d'image cachée. |
| W13 | `--from-file` vs `--from-env-file` pour ConfigMap/Secret | `--from-file=f` = **1 clé = nom du fichier**, valeur = tout le contenu. `--from-env-file=f` = **1 clé par ligne** `KEY=val`. Se tromper crée une structure inexploitable par `configMapKeyRef`. |
| W14 | `envFrom` sur un ConfigMap/Secret dont des clés ne sont pas des noms de variables valides | Clés avec `.`/`-` (ex `car.make`) = **invalides** comme env vars → K8s les **skippe silencieusement** (event `InvalidVariableNames`), le Pod démarre quand même sans elles. En **volume** ces mêmes clés passent (noms de fichiers OK). Vérifier avec `kubectl describe pod`. |

---

## 🌐 Services & Networking (domaine 03 — 20 %)

| # | Piège | Détail |
|---|---|---|
| N1 | Service sans **endpoints** | `endpoints` vides = le **selector** ne matche aucun Pod (labels KO) ou Pods pas `Ready`. `kubectl get ep <svc>`. |
| N2 | Confondre `port` / `targetPort` / `nodePort` | `port` = port du Service · `targetPort` = port du conteneur · `nodePort` = 30000-32767 sur les nodes. |
| N3 | NetworkPolicy sans **CNI compatible** | Flannel seul **n'applique pas** les NetPol. Il faut Calico/Cilium. |
| N4 | NetworkPolicy : croire qu'elle « autorise » globalement | Dès qu'une NetPol sélectionne un Pod, tout le **non-autorisé** est bloqué (deny implicite sur ce type). |
| N5 | Confondre `podSelector` et `namespaceSelector` dans `from` | Deux entrées séparées = OR ; sous le même `-` = AND. Piège fréquent. |
| N6 | Ingress sans **Ingress Controller** | La règle Ingress ne sert à rien sans controller déployé. |
| N7 | Oublier `pathType` (obligatoire en `networking.k8s.io/v1`) | `Prefix` le plus courant. |
| N8 | DNS : mauvais **FQDN** | `<svc>.<ns>.svc.cluster.local`. Debug via un Pod `busybox` + `nslookup`. |
| N9 | Croire que `containerPort` ouvre/configure un port | `containerPort` est **purement documentaire** — l'appli écoute où elle veut (nginx=80). `kubectl expose` **sans `--port`** reprend le `containerPort` comme `port`+`targetPort` → si l'appli n'écoute pas là, **endpoints OK mais connexion refusée**. Fix : `--target-port` = **vrai** port d'écoute. |
| N10 | Confondre « DNS résout » et « Service a des endpoints » | Un Service **ClusterIP** résout **toujours** vers sa ClusterIP, **même sans Pod matché** (CoreDNS crée un A record par Service existant). Donc un souci de **résolution** (NXDOMAIN) = namespace (short name cross-ns), Service inexistant, ou CoreDNS KO — **pas** les selectors. Les selectors/labels cassent les **endpoints** → « connexion refusée/timeout », **pas** « ne résout pas ». Exception : Service **headless** (sans endpoints → pas d'A record). |

---

## 💾 Storage (domaine 04 — 10 %)

| # | Piège | Détail |
|---|---|---|
| D1 | PVC `Pending` : ne pas comprendre pourquoi | Binding exige : accessModes compatibles + capacité PV ≥ PVC + **même storageClassName**. |
| D2 | `volumeBindingMode: WaitForFirstConsumer` | Le PVC reste `Pending` **exprès** jusqu'à ce qu'un Pod l'utilise. Normal, pas un bug → crée le Pod. |
| D3 | Le Pod référence le **PV** au lieu du **PVC** | Le Pod monte le **PVC** (`claimName`), jamais le PV directement. |
| D4 | `storageClassName: ""` vs absent | `""` (vide) = pas de provisioning dynamique (binding manuel). Absent = StorageClass par défaut. |
| D5 | Oublier `accessModes` ou `resources.requests.storage` | Les 2 champs minimaux obligatoires d'un PVC. |
| D6 | `reclaimPolicy` : Delete efface les données | `Retain` conserve le PV/données après suppression du PVC. |
| D7 | Nom de ressource invalide / mauvais suffixe de taille | Noms K8s = **minuscules** RFC 1123 (`10Gpv01` ❌ → `pv01`) : `Invalid value ... a lowercase RFC 1123 subdomain`. Quantité **case-sensitive** : `Gi`/`Mi` (`8GI`/`150mi` ❌) : serveur rejette avec `quantities must match the regular expression '^([+-]?[0-9.]+)([eEinumkKMGTP]*...)$'`. |

---

## 🧯 Troubleshooting (domaine 05 — 30 %, le plus gros !)

| # | Piège | Détail |
|---|---|---|
| T1 | Deviner au lieu de lire les **events** | `kubectl describe <res>` + `kubectl get events --sort-by=.metadata.creationTimestamp`. La réponse y est presque toujours. |
| T2 | Confondre les états de Pod | `Pending` = scheduling · `ContainerCreating` = image/volume · `CrashLoopBackOff` = appli qui crash · `ImagePullBackOff` = registry/secret. |
| T3 | Oublier `--previous` sur un pod qui a redémarré | `kubectl logs <pod> --previous` pour voir le crash précédent. |
| T4 | Node NotReady : ne pas SSH | `ssh <node>` → `systemctl status kubelet` + `journalctl -u kubelet -e`. Souvent kubelet down / swap on / containerd down. |
| T5 | Oublier `sudo` avec `crictl`/systemctl | Accès root nécessaire sur le node. |
| T6 | kubelet : ne pas connaître ses fichiers | Config : `/var/lib/kubelet/config.yaml` · service : `/etc/systemd/system/kubelet.service.d/` · après modif → `systemctl daemon-reload && systemctl restart kubelet`. |
| T7 | Réactivation du **swap** casse le kubelet | `swapoff -a` + commenter dans `/etc/fstab`. |
| T8 | Chercher la cause dans le mauvais composant | Remonte la chaîne : Pod → node → kubelet → runtime (containerd). |
| T9 | **Pods `Pending` sans event de ressources** = scheduler down | Personne ne remplit `spec.nodeName`. Vérifier `kubectl -n kube-system get pods -l component=kube-scheduler` (static pod → `/etc/kubernetes/manifests/kube-scheduler.yaml`). |
| T10 | **Pods supprimés non recréés / node mort non nettoyé** = controller-manager down | Plus d'auto-healing. Vérifier `kubectl -n kube-system get pods -l component=kube-controller-manager`. |
| T11 | Croire qu'un composant "parle" à un autre | Aucun messaging direct : **seul l'apiserver touche etcd** ; tous les autres composants **watch** l'API. Un composant réagit à un **champ** (ex. `nodeName` vide), pas à un ordre. |
| T12 | **Namespace bloqué en `Terminating`** | Une ressource dedans garde un **finalizer** non résolu. Diagnostic : `kubectl get ns <ns> -o yaml` (voir `spec.finalizers` + `status.conditions`) puis `kubectl api-resources --verbs=list --namespaced -o name \| xargs -n1 kubectl get -n <ns>` pour trouver l'objet coincé. Fix propre : vider le finalizer de **l'objet** → `kubectl patch <res> <name> -n <ns> --type=merge -p '{"metadata":{"finalizers":[]}}'`. Forcer le finalizer du **namespace** (`/finalize`) = dernier recours (laisse des ressources orphelines). |
| T13 | Pod `1/1 Running` ≠ appli OK | Un container peut être **Running** alors que le process **ne fait rien** (mauvais paramètre avalé silencieusement) ou a paniqué au boot. Ne jamais se fier au STATUS seul → **`kubectl logs`** systématique. Ex. LFS258 : `panic: unable to parse quantity's suffix` sur `150mi` (bon = `150Mi`) → le Pod passe `Error`/CrashLoop. |

---

## 🔒 Champs mutables vs immuables (`field is immutable`)

> Un champ **immuable** ne se modifie plus après création → il faut **delete + recreate** l'objet. Si un `apply`/`edit` renvoie `field is immutable`, c'est ici.

| Objet | Champ **immuable** | Contournement |
|---|---|---|
| Deployment / RS / STS / DS | `spec.selector` | delete/recreate (ou `kubectl replace --force -f`) — lien contrôleur→Pods |
| Service | `spec.clusterIP` | delete/recreate ; `type`/`ports`/`selector` sont **mutables** |
| Pod | quasi tout `spec` | Pod = immuable par design → on le **remplace** ; exceptions mutables : `image` (`set image`), `tolerations` (ajout), resize CPU/mém (1.33+) |
| PVC | `spec.resources.requests.storage` | **agrandir** possible si `allowVolumeExpansion: true` (jamais réduire) |
| PV | `capacity`, `accessModes` (en pratique) | delete/recreate ; `nodeAffinity` devenu **mutable en 1.35** (avant : immuable) |
| Job | `spec.template`, `spec.selector`, `completions` | delete/recreate |
| ConfigMap / Secret | rien **sauf** `immutable: true` posé volontairement | delete/recreate ; `immutable: true` = choix **perf** (kubelet arrête de watcher) |

> ⚠️ Piège Kustomize lié : `commonLabels` / `labels` avec `includeSelectors: true` injectent le label **dans le selector** → `apply -k` casse un Deployment déjà déployé (selector immuable). Cf. fiche 02 §Kustomize.
> ⚠️ Nuance Service : le `selector` d'un **Service** EST mutable ; celui d'un **Deployment/RS** ne l'est pas. Ne pas confondre.
> 🆕 **1.35** : `PersistentVolume.spec.nodeAffinity` est passé **mutable** (KEP #134339). Concerne surtout les PV `local` (affinité node). Faible valeur examinable mais version-spécifique CKA 1.35.

---

## 🩹 Erreurs de syntaxe / réflexes qui coûtent des secondes

- **Indentation YAML** : 2 espaces, jamais de tabs. Une erreur d'indentation = manifest rejeté.
- **`-n <ns>`** oublié → objet créé/cherché dans `default`. Vérifie toujours le namespace demandé.
- **`--all-namespaces` / `-A`** pour voir tout le cluster (pas `-n all` qui n'existe pas).
- **`vim` en mode collage** : `:set paste` avant de coller du YAML pour éviter l'auto-indent qui casse tout.
- **Apostrophes/guillemets** : les valeurs booléennes/numériques en label doivent être quotées (`gpu: "true"`).
- **`kubectl explain <res>.spec`** pour retrouver un champ sans quitter le terminal.

---

## 📚 Sources des retours communautaires

- Simulateur **killer.sh** (inclus avec l'inscription — la meilleure préparation).
- Forum Linux Foundation (Cloud & Containers Training).
- Retours agrégés : r/kubernetes, blogs de certifiés CKA, GitHub « CKA exercises ».
- Curriculum officiel CNCF + doc kubernetes.io.

> ⚠️ Ces pièges sont des **tendances**, pas une liste officielle. L'exam évolue (format PSI, contenu ajusté). Toujours croiser avec la doc officielle et killer.sh.

---

_Ajoute un piège ici en disant : « ajoute le piège sur <sujet> »._
