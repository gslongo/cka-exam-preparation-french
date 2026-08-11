# 🧪 CKA — Examen blanc n°3 · Drills ciblés (gaps)

> Set complémentaire : il **comble les thèmes CKA non couverts** par les examens n°1 et n°2
> (kubeconfig, etcd *restore*, CSR/kubeconfig user, HPA, DaemonSet, kubelet cassé, `crictl`, etc.).
> Les tâches y sont **indépendantes** : tu peux en jouer une seule à la fois.
> Barème provisoire — l'ensemble sera équilibré au fur et à mesure.

## Mise en place
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/setup.sh"   # sème l'état de départ
# … tu résous les tâches …
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/grade.sh"   # correction (lecture seule)
```
> `setup.sh` est **idempotent** : il nettoie les réponses précédentes avant de re-semer.
> Les solutions sont dans [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — à n'ouvrir qu'après.

---

## 🏛️ Cluster Architecture & kubeconfig

### T1 — Extraire des informations d'un kubeconfig (7 pts) · sur `cp1`
Un fichier kubeconfig **hors du cluster** est fourni : `/opt/exam-03/kubeconfig`.
Sans le fusionner avec ta config courante, extrais-en trois informations :

1. Écris **tous les noms de contextes** (un par ligne) dans `/opt/exam-03/contexts`.
2. Écris le **nom du contexte courant** dans `/opt/exam-03/current-context`.
3. Écris le **client-certificate** de l'utilisateur **`audit-user`**, **décodé depuis base64**, dans `/opt/exam-03/cert`.

> 💡 Tout se fait avec `kubectl config … --kubeconfig=/opt/exam-03/kubeconfig` (+ `base64 -d` pour le certificat). Ne modifie pas le kubeconfig fourni.
> Attendu : les 3 fichiers présents et exacts (l'ordre des contextes n'importe pas).

---

## 📦 Packaging & Helm

### T2 — Installer cert-manager avec Helm + ClusterIssuer (8 pts) · sur `cp1`
Installe **cert-manager** via Helm, puis crée un `ClusterIssuer`.

1. Crée le *Namespace* `pki`.
2. Installe le chart `jetstack/cert-manager` (avec `crds.enabled=true`) dans ce namespace. La *release* Helm doit s'appeler **`certman`**.
3. Édite le `ClusterIssuer` fourni dans `/opt/exam-03/issuer.yaml` pour ajouter `crlDistributionPoints: ["http://pki.cka.local/crl"]` sous `spec.selfSigned`.
4. Crée le `ClusterIssuer` à partir de `/opt/exam-03/issuer.yaml`.

> ℹ️ cert-manager n'a pas besoin d'émettre de vrais certificats : installer le chart + créer le `ClusterIssuer` suffit.
> ⚠️ Attends que les pods cert-manager soient **Ready** avant de créer le `ClusterIssuer`, sinon le webhook d'admission rejette la création.
> Attendu : release Helm `certman` dans `pki`, CRDs cert-manager présents, `ClusterIssuer selfsigned-issuer` créé avec `crlDistributionPoints`.

---

## 🧱 Workloads & Scheduling

### T3 — Scaler un StatefulSet (5 pts) · sur `cp1`
Dans le *Namespace* `project-store`, plusieurs *Pods* `store-db-*` tournent (un StatefulSet à 3 replicas).
Pour économiser des ressources, réduis ce StatefulSet à **1 seul replica**.

> 💡 Les Pods `store-db-*` appartiennent à un StatefulSet : trouve le contrôleur, puis change son nombre de replicas (ne supprime pas les Pods à la main — ils seraient recréés).
> Attendu : le StatefulSet `store-db` a `replicas: 1` et 1 Pod prêt.

### T4 — Identifier les Pods évincés en premier (QoS) (6 pts) · sur `cp1`
Dans le *Namespace* `project-qos`, inspecte tous les *Pods* et trouve ceux qui seraient **évincés en premier** si un nœud vient à manquer de ressources (CPU ou mémoire).
Écris leurs noms (**un par ligne**) dans `/opt/exam-03/qos-evicted-first.txt`.

> 💡 Sous pression de ressources (node-pressure eviction), l'ordre suit la **QoS class** : `BestEffort` d'abord, puis `Burstable`, et `Guaranteed` en dernier.
> Attendu : le fichier contient exactement les Pods de la QoS class la plus fragile (l'ordre des lignes n'importe pas).

---

## 🧩 HPA & Kustomize

### T5 — HPA via Kustomize (12 pts) · sur `cp1`
L'application `api-gw` a été déployée dans les *Namespaces* `api-gw-staging` et `api-gw-prod` via Kustomize :

```bash
kubectl kustomize /opt/exam-03/kustomize/api-gw/overlays/staging | kubectl apply -f -
kubectl kustomize /opt/exam-03/kustomize/api-gw/overlays/prod    | kubectl apply -f -
```

En partant de la config Kustomize dans `/opt/exam-03/kustomize/api-gw`, réalise :

1. Supprime complètement la *ConfigMap* `scaling-config`.
2. Ajoute un *HPA* nommé `api-gw` pour le *Deployment* `api-gw`, avec min `2` et max `4` replicas, ciblant **50 %** d'utilisation CPU moyenne.
3. En **prod**, l'HPA doit avoir max `6` replicas.
4. Applique tes changements pour staging **et** prod (reflétés dans le cluster).

> 💡 metrics-server n'est pas requis : seul l'objet HPA (min/max/cible) est évalué (la cible affichera `<unknown>`, c'est normal).
> ⚠️ `kubectl apply` ne **purge** pas les ressources retirées du kustomize — pense à supprimer la ConfigMap déjà présente dans le cluster.
> Attendu : HPA `api-gw` dans les 2 ns (staging max 4, prod max 6, cible 50 %), et `ConfigMap scaling-config` absente des 2 ns.

---

## 💾 Storage

### T6 — PV + PVC (sans StorageClass) monté par un Deployment (10 pts) · sur `cp1`
1. Crée un *PersistentVolume* `data-pv` : capacité **1Gi**, accessMode **ReadWriteOnce**, hostPath `/mnt/data-vol`, **sans** `storageClassName`.
2. Crée un *PersistentVolumeClaim* `data-pvc` dans le *Namespace* `storage-app` : demande **1Gi**, accessMode **ReadWriteOnce**, **sans** `storageClassName`. Il doit être **Bound** au PV.
3. Crée un *Deployment* `webstore` dans `storage-app`, image `httpd:2-alpine`, qui monte ce volume sur `/var/www/data`.

> 💡 « sans storageClassName » = ne définis pas ce champ du tout (ni sur le PV ni sur le PVC). Un PVC sans SC se lie à un PV sans SC.
> Attendu : PV `data-pv` **Bound**, PVC `data-pvc` **Bound** au PV, Deployment `webstore` (httpd:2-alpine) montant le PVC sur `/var/www/data`.

---

## 📊 Observabilité

### T7 — Scripts `kubectl top` (metrics-server) (10 pts) · sur `cp1`
Le *metrics-server* est installé dans le cluster. Écris deux scripts bash utilisant `kubectl` :

1. `/opt/exam-03/node.sh` : affiche l'usage des ressources des **nodes**.
2. `/opt/exam-03/pod.sh` : affiche l'usage des ressources des **Pods et de leurs conteneurs**.

> 💡 C'est `kubectl top`. Pour détailler chaque conteneur d'un Pod : option `--containers`.
> Attendu : `node.sh` invoque `kubectl top nodes` (et renvoie des métriques) ; `pod.sh` invoque `kubectl top pod --containers`.

---

## 🔧 Cycle de vie des nœuds (kubeadm)

### T8 — Jonction d'un worker + upgrade node (10 pts) · sur `cp1`
Un nouveau nœud *worker* doit rejoindre le cluster, et un worker existant en version plus ancienne doit être mis à niveau. **Sans modifier le cluster ni toucher aux nœuds**, prépare les deux artefacts suivants sur `cp1` :

1. Génère depuis le *control plane* une **commande de jonction complète** (avec `token` **réel** et *hash* du CA) et enregistre-la telle quelle dans `/opt/exam-03/join-command.txt`.
2. Rédige dans `/opt/exam-03/upgrade-node.sh` le **runbook d'upgrade d'un worker** : les commandes à exécuter *sur le worker* pour l'aligner sur la version du control plane (mise à niveau du paquet `kubelet`, `kubeadm upgrade node`, redémarrage du kubelet).

> 💡 La commande de jonction se génère en une fois avec `kubeadm token create --print-join-command`. Côté worker, on **n'utilise pas** `kubeadm upgrade apply` (réservé au control plane) mais `kubeadm upgrade node`.
> ⚠️ Tâche **non destructive** : tu ne joins ni ne mets à jour réellement un nœud ici — tu produis les artefacts. (killer.sh, lui, le fait pour de vrai sur son environnement.)
> Attendu : `join-command.txt` contient un `kubeadm join …:6443 --token … --discovery-token-ca-cert-hash sha256:…` avec un token existant ; `upgrade-node.sh` contient `kubeadm upgrade node` + mise à jour/redémarrage du kubelet.

---

## 🔐 API Kubernetes depuis un Pod

### T9 — Requêter l'API depuis un Pod via ServiceAccount (10 pts) · sur `cp1`
Dans le *Namespace* `project-audit`, la *ServiceAccount* `probe-sa` a le droit de lister les *Secrets* du namespace.

1. Crée un *Pod* nommé `secret-probe`, image `nginx:1-alpine`, qui **utilise la ServiceAccount `probe-sa`**.
2. Entre dans le Pod (`kubectl exec`) et, avec `curl`, interroge **manuellement** l'API Kubernetes pour lister **tous les Secrets** du namespace `project-audit` (en t'authentifiant avec le token de la ServiceAccount monté dans le Pod).
3. Écris la réponse JSON de l'API dans `/opt/exam-03/secrets.json`.

> 💡 Dans le Pod, le token et le CA sont montés sous `/var/run/secrets/kubernetes.io/serviceaccount/` ; l'API interne est joignable sur `https://kubernetes.default.svc`. `curl` s'authentifie avec l'en-tête `Authorization: Bearer <token>` et `--cacert ca.crt`. (`nginx:1-alpine` n'a pas `curl` → `apk add --no-cache curl` dans le Pod.)
> Attendu : Pod `secret-probe` (`nginx:1-alpine`) utilisant `probe-sa`, et `secrets.json` = réponse `SecretList` de l'API contenant le Secret `audit-key`.

---

## 🛰️ DaemonSet & scheduling

### T10 — DaemonSet sur tous les nœuds, control-plane compris (10 pts) · sur `cp1`
Dans le *Namespace* `project-batch`, crée un *DaemonSet* nommé `log-harvester` :

1. Image `httpd:2-alpine`, avec les labels `id=log-harvester` et `uuid=7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64`.
2. Chaque *Pod* demande **15 millicores** de CPU et **20 Mi** de mémoire (`requests`).
3. Les *Pods* doivent tourner sur **tous les nœuds**, **y compris le control-plane** (`cp1`).

> 💡 Par défaut le control-plane porte un *taint* `node-role.kubernetes.io/control-plane:NoSchedule` : pour y planifier un Pod, ajoute la *toleration* correspondante dans le template du DaemonSet.
> Attendu : DaemonSet `log-harvester` planifié et **Ready sur les 3 nœuds** (labels + requests conformes).

### T11 — Deployment multi-conteneurs + anti-affinité (10 pts) · sur `cp1`
Dans le *Namespace* `project-batch`, crée un *Deployment* nommé `edge-cache` :

1. **3 replicas**, avec le label `id=edge-node` sur le *Deployment* **et** ses *Pods*.
2. Deux conteneurs : `main` (image `nginx:1-alpine`) et `sidecar` (image `registry.k8s.io/pause:3.10`).
3. Il ne doit y avoir **qu'un seul** *Pod* de ce *Deployment* **par nœud** — utilise une **anti-affinité de Pod** avec `topologyKey: kubernetes.io/hostname`.

> ℹ️ Comme il n'y a que **2 nœuds workers** planifiables (le control-plane est *tainted*) et **3 replicas**, le **3e Pod restera `Pending`** — c'est le comportement attendu (à la manière d'un DaemonSet simulé).
> Attendu : Deployment `edge-cache` (3 replicas, label `id=edge-node`, conteneurs `main`+`sidecar`), anti-affinité `kubernetes.io/hostname`, **2 Pods `Running` + 1 `Pending`**.

---

## 🔐 Certificats du cluster

### T13 — Expiration & renouvellement des certificats kubeadm (10 pts) · sur `cp1`
Inspecte les certificats du control plane :

1. Regarde **combien de temps le certificat serveur `kube-apiserver` est valide** (avec `openssl` sur `/etc/kubernetes/pki/apiserver.crt`) et écris sa **date d'expiration** dans `/opt/exam-03/apiserver-expiration`. Confirme avec `kubeadm certs check-expiration` que les deux méthodes donnent la même date.
2. Écris dans `/opt/exam-03/renew-apiserver.sh` la **commande `kubeadm`** qui **renouvellerait** le certificat de `kube-apiserver` (ne l'exécute pas).

> 💡 `openssl x509 -noout -enddate -in …` donne le `notAfter` ; `kubeadm certs check-expiration` liste toutes les dates. Le renouvellement ciblé se fait avec `kubeadm certs renew <composant>`.
> Attendu : `apiserver-expiration` contient la date/année d'expiration du cert apiserver ; `renew-apiserver.sh` contient `kubeadm certs renew apiserver`.

---

## 🛡️ Réseau — NetworkPolicy egress

### T14 — Restreindre l'egress d'un backend (10 pts) · sur `cp1`
Suite à un incident, un *Pod* `backend-*` compromis a pu contacter tout le cluster. Dans le *Namespace* `project-mesh`, crée une *NetworkPolicy* nommée `np-egress` qui autorise les *Pods* `backend-*` à **uniquement** :

- se connecter aux *Pods* `cache-a-*` sur le port `6379` ;
- se connecter aux *Pods* `cache-b-*` sur le port `5432`.

Toute autre sortie (par ex. vers `audit-*` sur `9999`) doit être **bloquée**. Utilise les labels `app` des *Pods* dans ta politique.

> 💡 C'est une politique **egress** (`policyTypes: [Egress]`) : `podSelector` sélectionne `app=backend`, et chaque règle `egress` associe un `to.podSelector` (`app=cache-a` / `app=cache-b`) à son `ports`. Mets **une règle par cible** (sinon tu autorises le produit croisé des ports).
> Attendu : `np-egress` sélectionne `app=backend`, type `Egress`, autorise `app=cache-a:6379` et `app=cache-b:5432` (et rien d'autre).

---

## 🔎 Debug — runtime de conteneurs (`crictl`)

### T16 — Inspecter un conteneur avec `crictl` (10 pts) · sur `cp1`
Un *Pod* `probe-httpd` (image `httpd:2-alpine`) tourne dans le *Namespace* `project-batch`, sur le nœud `cp1`. `kubectl` ne suffit pas : tu dois passer par le **runtime** pour l'auditer. En te servant de `crictl` sur `cp1` :

1. Retrouve l'**ID du conteneur** de ce *Pod* et son **type de runtime** (champ `info.runtimeType` de `crictl inspect`), puis écris les deux dans `/opt/exam-03/container-info.txt`.
2. Récupère les **logs** du conteneur et écris-les dans `/opt/exam-03/container.log`.

> 💡 `sudo crictl ps` liste les conteneurs (colonne `NAME`/`POD`) ; `sudo crictl inspect <id>` donne le détail JSON (dont `.info.runtimeType`, souvent `io.containerd.runc.v2`) ; `sudo crictl logs <id>` sort les logs. Filtre avec `--name probe-httpd` ou `grep`.
> Attendu : `container-info.txt` contient un ID de conteneur (hexadécimal) **et** le type de runtime (`runc`) ; `container.log` existe.

---

## 🚪 Gateway API — routage HTTP

### T12 — Router le trafic avec une HTTPRoute (10 pts) · sur `cp1`
Le cluster expose déjà un *Gateway* `edge-gw` (classe `eg-class`) dans le *Namespace* `project-edge`. On remplace un ancien *Ingress* par l'API **Gateway**. Crée une *HTTPRoute* nommée `route-splitter` dans `project-edge`, rattachée au *Gateway* `edge-gw`, qui :

- route le préfixe de chemin `/web` vers le *Service* `web-svc:80` ;
- route le préfixe de chemin `/svc` vers le *Service* `api-svc:80` ;
- pour le préfixe `/shop` : route vers `premium-svc:80` **uniquement si** la requête porte l'en-tête **`X-Tier: premium`** (chemin **ET** en-tête dans le **même** *match*), et vers `standard-svc:80` **sinon** (catch-all `/shop`).

> 💡 API `gateway.networking.k8s.io/v1`, `kind: HTTPRoute`. Rattachement via `spec.parentRefs` (nom du *Gateway*). Un `match` qui liste à la fois `path` **et** `headers` applique un **ET logique** (les deux doivent correspondre) ; les séparer en deux `matches` donnerait un **OU**. Place la règle `/shop` + en-tête **avant** le catch-all `/shop` : l'**ordre des règles compte** (la première qui correspond gagne). Les *Services* n'ont pas besoin d'exister pour valider l'objet.
> Attendu : `route-splitter` référence `edge-gw` ; route `/web` et `/svc` par préfixe ; `/shop` + `X-Tier: premium` → premium ; `/shop` seul → standard.

---

## 🧭 CoreDNS — domaine personnalisé

### T15 — Ajouter un domaine à CoreDNS (10 pts) · sur `cp1`
CoreDNS résout le DNS interne via la *ConfigMap* `coredns` (*Namespace* `kube-system`). On veut que les noms de la forme `SERVICE.NAMESPACE.svc.cka.local` résolvent **exactement** comme leurs équivalents `…svc.cluster.local`.

1. **Sauvegarde d'abord** la *ConfigMap* `coredns` complète dans `/opt/exam-03/coredns_original.yaml`.
2. Modifie le **Corefile** pour que le domaine `cka.local` soit servi par le plugin `kubernetes` (au même titre que `cluster.local`).

> 💡 `kubectl -n kube-system get cm coredns -o yaml` pour la sauvegarde ; `kubectl -n kube-system edit cm coredns` pour éditer. Sur la ligne du plugin `kubernetes`, ajoute la zone : `kubernetes cluster.local cka.local in-addr.arpa ip6.arpa { … }`. Recharge avec `kubectl -n kube-system rollout restart deployment coredns` (ou attends le plugin `reload`).
> Attendu : `coredns_original.yaml` est la sauvegarde de la *ConfigMap* `coredns` ; le Corefile actif déclare `cka.local` sur la ligne du plugin `kubernetes`.

---

## 🗄️ etcd — introspection

### T17 — Informations sur etcd (9 pts) · sur `cp1`
etcd s'exécute en *static Pod* sur `cp1`. **Sans rien modifier**, retrouve les informations suivantes et écris-les dans `/opt/exam-03/etcd-info.txt` :

- l'emplacement de la **clé privée serveur** d'etcd ;
- la **date d'expiration** du **certificat serveur** d'etcd ;
- si l'**authentification par certificat client** est activée (oui/non).

> 💡 Le manifeste `/etc/kubernetes/manifests/etcd.yaml` liste les drapeaux d'etcd (`--key-file`, `--cert-file`, `--client-cert-auth`). `openssl x509 -noout -enddate -in <cert>` donne la date d'expiration. Le format libre du fichier n'a pas d'importance, tant que les trois informations y figurent.
> Attendu : `etcd-info.txt` contient le chemin de `server.key`, l'année d'expiration du cert serveur, et l'état de `client-cert-auth`.

---

## 🔀 kube-proxy — mode iptables

### T18 — Règles iptables d'un Service (8 pts) · sur `cp1`
Le cluster utilise **kube-proxy en mode iptables**. Dans le namespace `project-proxy` (déjà créé) :

- crée un Pod `p-proxy` à partir de l'image `nginx:1-alpine` ;
- expose-le avec un Service **ClusterIP** nommé `proxy-svc` sur le port **3100**, redirigé vers le port **80** du conteneur ;
- écris dans `/opt/exam-03/iptables.txt` les **règles iptables** (table `nat`) générées par kube-proxy pour ce Service.

> 💡 `sudo iptables-save -t nat | grep proxy-svc` (ou `grep <clusterIP>`). Les chaînes `KUBE-SERVICES` → `KUBE-SVC-*` portent le trafic vers le Service. **Garde le Service en place** pour la correction.
> Attendu : Pod `p-proxy` en cours d'exécution, Service `proxy-svc` (3100→80), `iptables.txt` contient les règles `KUBE-SVC` du Service.

---

## 🌐 Service CIDR — étendre la plage d'IP des Services

### T19 — Ajouter une plage d'IP de Services (10 pts) · sur `cp1`
**Sans redémarrer le kube-apiserver**, tu vas ajouter une nouvelle plage d'IP de Services au cluster grâce à l'API **ServiceCIDR** (GA). Dans le namespace `project-range` (déjà créé) :

- crée un Pod `range-probe` à partir de l'image `httpd:2-alpine` ;
- expose-le avec un premier Service **ClusterIP** `range-svc` sur le port **80** (il obtient une IP de la plage par défaut) ;
- crée un objet **ServiceCIDR** nommé `extra-range` couvrant la plage **`12.64.0.0/12`** ;
- crée un second Service **ClusterIP** `range-svc2` vers le **même** Pod (port 80), en lui attribuant une **clusterIP appartenant à `12.64.0.0/12`**.

> 💡 `kubectl get servicecidr` montre la plage par défaut (`kubernetes`). Un ServiceCIDR **additif** étend les plages sans toucher au drapeau `--service-cluster-ip-range`. Pour `range-svc2`, fixe `spec.clusterIP` dans `12.64.0.0/12` (ex. `12.64.0.10`).
> Attendu : ServiceCIDR `extra-range` (`12.64.0.0/12`) présent ; `range-svc2` possède une clusterIP comprise dans `12.64.0.0/12`.
