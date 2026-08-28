# 🌐 Lab — Services · Ingress · Gateway API

> **Lab thématique** (pas un examen blanc) : il se concentre sur l'**exposition du trafic**
> en trois couches — *Services* (L4), *Ingress* (L7 « historique »), *Gateway API* (L7 moderne).
> Les tâches sont **indépendantes** et de difficulté progressive : tu peux en jouer une seule à la fois.
> **100 pts**, objectif **≥ 75 %**. Pas de limite de temps — c'est un lab d'entraînement.

> ⚠️ **Aucun contrôleur Ingress ni Gateway n'est installé** (comme souvent au CKA) : pour ces deux
> couches, le grader **note l'objet Kubernetes** (déclaration correcte : classe, hôtes, chemins,
> backends, en-têtes, poids…), pas le trafic réel. Pour les **Services**, la connectivité est
> **testée en direct** (un Pod `probe` se connecte aux ClusterIP).

## Mise en place
```bash
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/setup.sh"   # sème l'état de départ
# … tu résous les tâches …
vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"   # correction (lecture seule)
```
> `setup.sh` est **idempotent** : il recrée les namespaces `services-lab`, `ingress-lab`, `gateway-lab`
> et (si besoin) installe les CRD **Gateway API**. Il nettoie tes réponses précédentes avant de re-semer.
> Les solutions sont dans [`solutions/SOLUTIONS.md`](solutions/SOLUTIONS.md) — à n'ouvrir qu'après.

---

## 🔌 Domaine A — Services (40 pts) · Namespace `services-lab`

### A1 — Exposer un Deployment en ClusterIP (10 pts)
Un *Deployment* `web` (2 replicas, `app=web`, conteneur sur le port **80**) tourne déjà.
Crée un *Service* **ClusterIP** nommé `web-svc` qui l'expose sur le port **80 → 80**.

> 💡 `kubectl expose deployment web --name web-svc --port 80 --target-port 80` (type ClusterIP par défaut). Vérifie que les *endpoints* se peuplent : `kubectl -n services-lab get endpoints web-svc`.
> Attendu : `web-svc` de type `ClusterIP`, port `80→80`, selector `app=web`, **2 endpoints** prêts et joignables sur `:80`.

### A2 — Exposer le même Deployment en NodePort (8 pts)
Expose aussi `web` avec un second *Service* nommé `web-np` de type **NodePort**, port **80 → 80**,
en fixant le **nodePort** à **`30080`**.

> 💡 `kubectl expose … --type NodePort …` attribue un nodePort aléatoire ; pour **imposer** `30080`, édite le Service (ou pars d'un YAML avec `spec.ports[0].nodePort: 30080`).
> Attendu : `web-np` de type `NodePort`, `nodePort=30080`, port `80→80`, selector `app=web`.

### A3 — Service headless pour un ensemble de Pods (8 pts)
Un *Deployment* `cache` (2 replicas, `app=cache`) tourne. Crée un *Service* **headless** nommé
`cache-hl` (**sans** IP de cluster) sur le port **80**, qui sélectionne ces Pods.

> 💡 Un Service *headless* se déclare avec `spec.clusterIP: None`. Il ne fait pas d'équilibrage : le DNS renvoie **directement les IP des Pods**. Vérifie : `kubectl -n services-lab get endpoints cache-hl` (les 2 IP doivent apparaître).
> Attendu : `cache-hl` avec `clusterIP: None`, selector `app=cache`, port `80`, **2 adresses** d'endpoints.

### A4 — Service sans selector + Endpoints manuels (8 pts)
Un Pod `legacy-db` (label `app=legacy-db`) écoute sur le port **5432** — imagine une base « externe »
que tu veux joindre via un nom de Service stable. Crée :

1. un *Service* **ClusterIP** `db-ext` **sans selector**, port **5432 → 5432** ;
2. un objet **Endpoints** `db-ext` (même nom que le Service) qui pointe vers l'**IP du Pod `legacy-db`** sur le port **5432**.

> 💡 Récupère l'IP : `kubectl -n services-lab get pod legacy-db -o wide` (colonne `IP`). Un Service sans selector **ne crée pas** d'Endpoints automatiquement → tu dois créer l'objet `Endpoints` à la main (même nom que le Service). Le nom d'`EndpointSlice` fonctionne aussi, mais l'`Endpoints` classique est le plus rapide.
> Attendu : `db-ext` **sans** selector (port 5432), un `Endpoints db-ext` avec ≥1 adresse, et la connexion `clusterIP:5432` aboutit bien à `legacy-db`.

### A5 — Réparer un Service cassé (6 pts)
Le *Service* `shop-svc` est censé exposer le *Deployment* `shop` (2 replicas, `app=shop`, port **80**),
mais **aucun endpoint** n'apparaît. Diagnostique et **corrige** le Service (ne le supprime pas).

> 💡 `kubectl -n services-lab get endpoints shop-svc` renvoie vide ⇒ le Service ne « matche » aucun Pod prêt. Compare le `spec.selector` et le `targetPort` du Service avec les labels/port réels des Pods `shop` (`kubectl -n services-lab get pods --show-labels`). Corrige avec `kubectl edit svc shop-svc`.
> Attendu : `shop-svc` a des endpoints peuplés et répond sur `:80`.

---

## 🌐 Domaine B — Ingress (30 pts) · Namespace `ingress-lab`

> Une *IngressClass* `lab-nginx` et trois *Services* backends (`web-svc`, `app-svc`, `api-svc`, tous
> ClusterIP:80) sont déjà présents. Le grader **note les objets Ingress** (aucun contrôleur n'est installé).

### B1 — Ingress simple, hôte + chemin (10 pts)
Crée un *Ingress* nommé `site` (classe `lab-nginx`) qui route l'hôte **`web.cka.local`**,
chemin **`/`** de type **`Prefix`**, vers le *Service* **`web-svc`** port **80**.

> 💡 `spec.ingressClassName: lab-nginx`. Chaque règle porte un `host`, et chaque chemin un `pathType` (`Prefix` ici) + un `backend.service.name`/`port.number`. `kubectl create ingress` accepte la syntaxe `--rule="web.cka.local/*=web-svc:80"` (à ajuster pour le pathType).
> Attendu : `site` — `ingressClassName=lab-nginx`, host `web.cka.local`, chemin `/` (Prefix) → `web-svc:80`.

### B2 — Ingress « fanout » multi-chemins (10 pts)
Crée un *Ingress* nommé `apps` pour l'hôte **`apps.cka.local`** qui répartit selon le chemin :

- **`/app`** (Prefix) → *Service* **`app-svc`** port **80** ;
- **`/api`** (Prefix) → *Service* **`api-svc`** port **80**.

> 💡 Un seul `host`, deux entrées sous `http.paths`, chacune avec son `pathType: Prefix` et son backend. Ordre indifférent ici (chemins disjoints).
> Attendu : `apps` — host `apps.cka.local`, `/app`→`app-svc:80` et `/api`→`api-svc:80` (Prefix).

### B3 — Ingress avec TLS (10 pts)
Sécurise un hôte en TLS :

1. Crée un *Secret* TLS nommé **`secure-tls`** (type `kubernetes.io/tls`) — un certificat auto-signé pour **`secure.cka.local`** suffit.
2. Crée un *Ingress* nommé `secure` pour l'hôte **`secure.cka.local`**, avec un bloc **`tls`** référençant `secure-tls`, et une règle chemin **`/`** → *Service* **`web-svc`** port **80**.

> 💡 Génère la paire avec `openssl req -x509 -newkey rsa:2048 -nodes -keyout tls.key -out tls.crt -days 365 -subj "/CN=secure.cka.local"`, puis `kubectl -n ingress-lab create secret tls secure-tls --cert=tls.crt --key=tls.key`. Dans l'Ingress, `spec.tls: [{ hosts: [secure.cka.local], secretName: secure-tls }]`.
> Attendu : Secret `secure-tls` (type TLS) ; Ingress `secure` avec `tls.secretName=secure-tls`, `tls.hosts[0]=secure.cka.local`, règle host `secure.cka.local` `/`→`web-svc:80`.

---

## 🚪 Domaine C — Gateway API (30 pts) · Namespace `gateway-lab`

> Un *GatewayClass* `lab-gwc` et un *Gateway* `edge` (listener HTTP:80) sont déjà déployés, ainsi que les
> *Services* backends (`web-svc`, `api-svc`, `gold-svc`, `std-svc`, `canary-v1`, `canary-v2`, tous ClusterIP:80).
> Tu crées uniquement les **HTTPRoute** (`gateway.networking.k8s.io/v1`). Le grader note les objets.

### C1 — HTTPRoute : routage par préfixe (10 pts)
Crée une *HTTPRoute* nommée `main-route`, rattachée au *Gateway* **`edge`**, qui route :

- le préfixe **`/web`** → *Service* **`web-svc`** port **80** ;
- le préfixe **`/api`** → *Service* **`api-svc`** port **80**.

> 💡 `spec.parentRefs: [{ name: edge }]`. Chaque règle : `matches[].path` (`type: PathPrefix`, `value: /web`) et `backendRefs[]` (`name`, `port`). Une règle par chemin.
> Attendu : `main-route` référence `edge` ; `/web`→`web-svc:80` et `/api`→`api-svc:80`.

### C2 — HTTPRoute : match sur en-tête + catch-all (10 pts)
Crée une *HTTPRoute* nommée `tier-route`, rattachée à **`edge`**, pour le préfixe **`/shop`** :

- si la requête porte l'en-tête **`X-Tier: gold`** → *Service* **`gold-svc`** port **80** (chemin **ET** en-tête dans le **même** *match*) ;
- **sinon** (`/shop` seul, sans en-tête) → *Service* **`std-svc`** port **80**.

> 💡 Un `match` qui liste à la fois `path` **et** `headers` applique un **ET logique**. Mets la règle `/shop` + en-tête **avant** le catch-all `/shop` : **l'ordre des règles compte** (la première qui matche gagne). Sépare-les en **deux règles** distinctes (chacune son `backendRefs`).
> Attendu : `tier-route` — `/shop` + `X-Tier: gold` (même match) → `gold-svc` ; `/shop` seul → `std-svc`.

### C3 — HTTPRoute : répartition pondérée (canary) (10 pts)
Crée une *HTTPRoute* nommée `canary-route`, rattachée à **`edge`**, qui envoie le trafic du chemin **`/`**
vers **deux** backends avec des **poids** :

- **`canary-v1`** port **80**, poids **90** ;
- **`canary-v2`** port **80**, poids **10**.

> 💡 Une seule règle avec **deux** entrées dans `backendRefs`, chacune avec son champ `weight`. La répartition est proportionnelle à la somme des poids (ici 90/100 et 10/100).
> Attendu : `canary-route` (rattachée à `edge`) avec `canary-v1` weight **90** et `canary-v2` weight **10** dans la même règle.

---

_Ce lab est extensible : dis « ajoute une tâche sur `<sujet>` » (ex. `ExternalName`, `sessionAffinity`, `ReferenceGrant` cross-namespace, `Gateway` multi-listener…)._
