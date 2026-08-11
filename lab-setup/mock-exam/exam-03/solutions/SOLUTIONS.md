# ✅ CKA — Examen blanc n°3 (drills ciblés) · SOLUTIONS

> **N'ouvre ce fichier qu'après ta tentative.** Chaque solution correspond exactement aux critères de `grade.sh`.
> Toutes les commandes sont à lancer depuis `cp1` (`vagrant ssh cp1`).

---

## 🏛️ Cluster Architecture & kubeconfig

### T1 — Extraire des informations d'un kubeconfig
On travaille uniquement sur le fichier fourni via `--kubeconfig` (sans toucher à `~/.kube/config`).

```bash
KC=/opt/exam-03/kubeconfig

# 1) Tous les noms de contextes, un par ligne
kubectl config --kubeconfig=$KC get-contexts -o name > /opt/exam-03/contexts
#   (équivalent jsonpath : kubectl config --kubeconfig=$KC view \
#      -o jsonpath='{range .contexts[*]}{.name}{"\n"}{end}' )

# 2) Contexte courant
kubectl config --kubeconfig=$KC current-context > /opt/exam-03/current-context

# 3) client-certificate de audit-user, décodé depuis base64
kubectl config --kubeconfig=$KC view --raw \
  -o jsonpath="{.users[?(@.name=='audit-user')].user.client-certificate-data}" \
  | base64 -d > /opt/exam-03/cert

# Vérif
cat /opt/exam-03/contexts
cat /opt/exam-03/current-context
head -1 /opt/exam-03/cert     # -----BEGIN CERTIFICATE-----
```

> Points clés testés :
> - `kubectl config get-contexts -o name` (ou jsonpath `.contexts[*].name`) pour lister.
> - `kubectl config current-context` pour le contexte actif.
> - `view --raw` est **indispensable** : sans `--raw`, les données de certificat sont masquées (`DATA+OMITTED`).
> - `base64 -d` pour décoder `client-certificate-data`.

---

## 📦 Packaging & Helm

### T2 — Installer cert-manager avec Helm + ClusterIssuer
```bash
# 1) Namespace
kubectl create namespace pki

# 2) Repo + install du chart (release 'certman', CRDs incluses)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install certman jetstack/cert-manager \
  --namespace pki \
  --set crds.enabled=true

# Attendre que cert-manager (surtout le webhook) soit prêt AVANT de créer le ClusterIssuer
kubectl -n pki rollout status deploy/certman-cert-manager-webhook
kubectl -n pki get pods

# 3) Éditer le ClusterIssuer fourni : ajouter crlDistributionPoints sous spec.selfSigned
#    /opt/exam-03/issuer.yaml devient :
#    spec:
#      selfSigned:
#        crlDistributionPoints:
#        - http://pki.cka.local/crl

# 4) Créer le ClusterIssuer
kubectl apply -f /opt/exam-03/issuer.yaml

# Vérif
helm list -n pki
kubectl get clusterissuer selfsigned-issuer -o jsonpath='{.spec.selfSigned.crlDistributionPoints[0]}{"\n"}'
```

> Points clés testés :
> - `helm repo add` + `helm install <release> <chart> -n <ns> --set crds.enabled=true`.
> - Les CRDs (`clusterissuers.cert-manager.io`, etc.) sont posées par le chart.
> - **Attendre le webhook** : sans ça, `kubectl apply` du ClusterIssuer échoue (`failed calling webhook`).
> - Éditer un manifeste de CR puis `kubectl apply -f`.

---

## 🧱 Workloads & Scheduling

### T3 — Scaler un StatefulSet
```bash
# 1) Identifier le contrôleur propriétaire des pods store-db-*
kubectl -n project-store get statefulset

# 2) Scaler à 1 replica (deux façons équivalentes)
kubectl -n project-store scale statefulset store-db --replicas=1
# ou : kubectl -n project-store edit statefulset store-db   → spec.replicas: 1

# 3) Vérif
kubectl -n project-store get statefulset store-db
kubectl -n project-store get pods
```

> Points clés testés :
> - Comprendre que des Pods `xxx-0/1/2` appartiennent à un **StatefulSet** (pas un Deployment).
> - `kubectl scale statefulset` (ou `edit`) plutôt que supprimer les Pods (qui seraient recréés).
> - Un StatefulSet supprime les Pods dans l'ordre **inverse** : `store-db-2` puis `store-db-1`, en gardant `store-db-0`.

### T4 — Pods évincés en premier (QoS BestEffort)
```bash
# Voir la QoS class de chaque Pod
kubectl -n project-qos get pods \
  -o custom-columns='NAME:.metadata.name,QOS:.status.qosClass'
# ou : kubectl -n project-qos get pod <name> -o jsonpath='{.status.qosClass}'

# Les BestEffort sont évincés en premier → écrire leurs noms (un par ligne)
printf '%s\n' web-cache log-agent > /opt/exam-03/qos-evicted-first.txt
```

> Rappel QoS :
> - **Guaranteed** : `requests == limits` pour CPU **et** mémoire, sur tous les conteneurs.
> - **Burstable** : au moins une `request` définie, mais pas Guaranteed.
> - **BestEffort** : aucune `request`/`limit` → **évincé en premier** sous node-pressure.

### T5 — HPA via Kustomize
```bash
cd /opt/exam-03/kustomize/api-gw

# 1) Manifeste HPA dans la base (autoscaling/v2)
cat > base/hpa.yaml <<'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gw
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gw
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

# 2) base/kustomization.yaml : retirer configmap.yaml, ajouter hpa.yaml
cat > base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
- hpa.yaml
EOF

# 3) overlays/prod : patch JSON6902 pour maxReplicas=6
cat > overlays/prod/kustomization.yaml <<'EOF'
namespace: api-gw-prod
resources:
- ../../base
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: api-gw
  patch: |-
    - op: replace
      path: /spec/maxReplicas
      value: 6
EOF

# 4) apply ne purge pas → supprimer la ConfigMap déjà dans le cluster
kubectl -n api-gw-staging delete configmap scaling-config
kubectl -n api-gw-prod    delete configmap scaling-config

# 5) Appliquer staging + prod
kubectl kustomize overlays/staging | kubectl apply -f -
kubectl kustomize overlays/prod    | kubectl apply -f -

# Vérif
kubectl -n api-gw-staging get hpa api-gw
kubectl -n api-gw-prod    get hpa api-gw
```

> Points clés testés :
> - `kubectl apply` ne supprime pas une ressource retirée du kustomize → supprimer la ConfigMap explicitement (ou `kubectl apply --prune`).
> - Overlay **prod** : un **patch JSON6902** modifie `maxReplicas` sans redéfinir tout l'HPA (DRY).
> - HPA en `autoscaling/v2` avec `metrics[].resource.target.averageUtilization: 50`.

### T6 — PV + PVC (sans SC) monté par un Deployment
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /mnt/data-vol
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage-app
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webstore
  namespace: storage-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webstore
  template:
    metadata:
      labels:
        app: webstore
    spec:
      containers:
      - name: httpd
        image: httpd:2-alpine
        volumeMounts:
        - name: data
          mountPath: /var/www/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: data-pvc
EOF

# Vérif du binding
kubectl get pv data-pv
kubectl -n storage-app get pvc data-pvc
kubectl -n storage-app get deploy webstore
```

> Points clés testés :
> - **Ni le PV ni le PVC** ne définissent `storageClassName` → le PVC (SC vide) se lie au PV (SC vide). S'il y avait une *default StorageClass*, il faudrait mettre `storageClassName: ""` explicitement.
> - Le volume se déclare sous `spec.template.spec.volumes` d'un **Deployment** (pas directement dans un Pod), avec le `volumeMount` côté conteneur.
> - `capacity` côté PV vs `resources.requests.storage` côté PVC.

### T7 — Scripts `kubectl top`
```bash
cat > /opt/exam-03/node.sh <<'EOF'
kubectl top nodes
EOF

cat > /opt/exam-03/pod.sh <<'EOF'
kubectl top pods --containers
EOF
chmod +x /opt/exam-03/node.sh /opt/exam-03/pod.sh

# Test
bash /opt/exam-03/node.sh
bash /opt/exam-03/pod.sh
```

> Notes :
> - `--containers` détaille chaque conteneur d'un Pod (utile pour les Pods multi-conteneurs).
> - Ajoute `-A` (`--all-namespaces`) pour couvrir tous les namespaces.
> - metrics-server met ~15-30 s à collecter après démarrage (`kubectl top` renvoie une erreur avant).

### T8 — Jonction d'un worker + upgrade node
```bash
# 1) Commande de jonction générée depuis le control plane (token réel + hash CA)
sudo kubeadm token create --print-join-command | tee /opt/exam-03/join-command.txt
#   → kubeadm join 192.168.56.10:6443 --token abcdef.0123456789abcdef \
#         --discovery-token-ca-cert-hash sha256:<hash>

# 2) Runbook d'upgrade d'un WORKER (à exécuter SUR le worker, pas sur cp1)
cat > /opt/exam-03/upgrade-node.sh <<'EOF'
#!/usr/bin/env bash
# Sur le worker — aligner sur la version exacte du control plane (ex : v1.35.x)

# a) basculer le dépôt apt sur la bonne mineure puis installer kubeadm cible
sudo sed -i 's#v1\.[0-9]*/deb#v1.35/deb#' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm='1.35.0-1.1'   # adapter au patch du control plane
sudo apt-mark hold kubeadm

# b) mettre à niveau la config kubelet du nœud (worker → 'upgrade node', PAS 'apply')
sudo kubeadm upgrade node

# c) drain depuis un poste admin :  kubectl drain <node> --ignore-daemonsets
# d) mettre à jour kubelet + kubectl puis redémarrer le service
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet='1.35.0-1.1' kubectl='1.35.0-1.1'
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# e) uncordon depuis un poste admin :  kubectl uncordon <node>
EOF
chmod +x /opt/exam-03/upgrade-node.sh
```

> Points clés testés :
> - `kubeadm token create --print-join-command` produit **token + endpoint + hash CA** en une commande — c'est le moyen recommandé d'ajouter un worker (le token du bootstrap initial expire après 24 h).
> - Différence clé : le **control plane** utilise `kubeadm upgrade apply <version>`, un **worker** utilise `kubeadm upgrade node` (met seulement à jour la config kubelet locale).
> - Ordre worker : dépôt apt → `kubeadm` → `kubeadm upgrade node` → drain → `kubelet`/`kubectl` → `restart kubelet` → uncordon. La version doit correspondre **exactement** à celle du control plane (règle de version-skew : kubelet ≤ kube-apiserver).

### T9 — Requêter l'API Kubernetes depuis un Pod (via ServiceAccount)
```bash
# 1) Pod utilisant la ServiceAccount probe-sa
kubectl -n project-audit run secret-probe --image=nginx:1-alpine \
  --overrides='{"spec":{"serviceAccountName":"probe-sa"}}'
kubectl -n project-audit wait --for=condition=Ready pod/secret-probe --timeout=60s

# 2) Depuis le Pod : token + CA montés dans /var/run/secrets/kubernetes.io/serviceaccount
kubectl -n project-audit exec secret-probe -- sh -c '
  apk add --no-cache curl >/dev/null 2>&1
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  curl -s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/namespaces/$NS/secrets
' > /opt/exam-03/secrets.json

cat /opt/exam-03/secrets.json    # SecretList JSON contenant audit-key
```

> Points clés testés :
> - Le Pod doit référencer la SA via `spec.serviceAccountName` (sinon le token monté est celui de la SA `default`, sans droits).
> - Le token JWT et le CA sont montés sous `/var/run/secrets/kubernetes.io/serviceaccount/` ; l'API interne répond sur `https://kubernetes.default.svc`.
> - La réponse est un `SecretList` **car** la SA a un `Role`/`RoleBinding` `get,list secrets` sur le namespace (sans RBAC → HTTP 403 `Forbidden`).

### T10 — DaemonSet sur tous les nœuds (control-plane compris)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-harvester
  namespace: project-batch
  labels:
    id: log-harvester
    uuid: 7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64
spec:
  selector:
    matchLabels:
      id: log-harvester
  template:
    metadata:
      labels:
        id: log-harvester
        uuid: 7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane   # planifier aussi sur cp1
        operator: Exists
        effect: NoSchedule
      containers:
      - name: harvester
        image: httpd:2-alpine
        resources:
          requests:
            cpu: 15m
            memory: 20Mi
EOF

kubectl -n project-batch get ds log-harvester -o wide   # DESIRED == nb de nœuds
```

> Points clés testés :
> - Un DaemonSet planifie **un Pod par nœud** éligible. Sans *toleration*, le control-plane (taint `NoSchedule`) est exclu → `DESIRED` = nb de workers seulement.
> - La *toleration* `node-role.kubernetes.io/control-plane` (Exists/NoSchedule) permet d'inclure `cp1` → `DESIRED` = nb total de nœuds.
> - Les `requests` (`cpu`/`memory`) et les labels sont définis dans le **template** du Pod.

### T11 — Deployment multi-conteneurs + anti-affinité
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-cache
  namespace: project-batch
  labels:
    id: edge-node
spec:
  replicas: 3
  selector:
    matchLabels:
      id: edge-node
  template:
    metadata:
      labels:
        id: edge-node
    spec:
      affinity:
        podAntiAffinity:                       # 1 seul Pod par nœud
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                id: edge-node
            topologyKey: kubernetes.io/hostname
      containers:
      - name: main
        image: nginx:1-alpine
      - name: sidecar
        image: registry.k8s.io/pause:3.10
EOF

kubectl -n project-batch get pods -l id=edge-node -o wide   # 2 Running + 1 Pending
```

> Points clés testés :
> - `podAntiAffinity` **required** avec `topologyKey: kubernetes.io/hostname` → le scheduler refuse deux Pods du même label sur le même nœud.
> - 2 workers planifiables + 3 replicas → le 3e Pod reste `Pending` (`0/x nodes available: didn't match pod anti-affinity`).
> - Un `Deployment` peut porter **plusieurs conteneurs** dans le même Pod (ici `pause` sert de conteneur d'appoint).

### T13 — Expiration & renouvellement des certificats kubeadm
```bash
# 1) Date d'expiration du certificat serveur kube-apiserver (openssl)
sudo openssl x509 -noout -enddate -in /etc/kubernetes/pki/apiserver.crt
#   notAfter=Aug  8 12:34:56 2026 GMT
sudo openssl x509 -noout -enddate -in /etc/kubernetes/pki/apiserver.crt \
  | cut -d= -f2 > /opt/exam-03/apiserver-expiration

# Confirmer avec kubeadm (même date attendue)
sudo kubeadm certs check-expiration | grep apiserver

# 2) Commande de renouvellement ciblée (ne pas l'exécuter)
echo 'sudo kubeadm certs renew apiserver' > /opt/exam-03/renew-apiserver.sh
```

> Points clés testés :
> - `openssl x509 -enddate` et `kubeadm certs check-expiration` renvoient la **même** date `notAfter` pour `apiserver`.
> - Le renouvellement peut être **global** (`kubeadm certs renew all`) ou **ciblé** (`kubeadm certs renew apiserver`) ; ici on cible `apiserver`.
> - Après un vrai renew, il faut redémarrer les Pods statiques du control plane (kube-apiserver) pour recharger le certificat.

### T14 — NetworkPolicy egress (backend → cache-a/cache-b uniquement)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: np-egress
  namespace: project-mesh
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes: [Egress]
  egress:
  - to:                                  # règle 1 : cache-a:6379
    - podSelector:
        matchLabels:
          app: cache-a
    ports:
    - protocol: TCP
      port: 6379
  - to:                                  # règle 2 : cache-b:5432
    - podSelector:
        matchLabels:
          app: cache-b
    ports:
    - protocol: TCP
      port: 5432
EOF

# Vérifier l'enforcement (par IP, sans dépendre du DNS) :
CA=$(kubectl -n project-mesh get pod -l app=cache-a -o jsonpath='{.items[0].status.podIP}')
VA=$(kubectl -n project-mesh get pod -l app=vault   -o jsonpath='{.items[0].status.podIP}')
kubectl -n project-mesh exec backend-1 -- /agnhost connect "$CA:6379" --timeout=3s   # OK (autorisé)
kubectl -n project-mesh exec backend-1 -- /agnhost connect "$VA:9999" --timeout=3s   # TIMEOUT (bloqué)
```

> Points clés testés :
> - Politique **egress** : dès qu'un Pod `backend` est sélectionné avec `policyTypes: [Egress]`, **toute** sortie non listée est refusée (donc `vault:9999` est bloqué).
> - **Une règle `egress` par cible** → `cache-a` n'est joignable que sur `6379`, `cache-b` que sur `5432`. Fusionner les `to`/`ports` dans une seule règle autoriserait le **produit croisé** (cache-a:5432, cache-b:6379) — trop permissif.
> - En pratique, pense à autoriser aussi l'egress DNS (`UDP/TCP 53`) si les Pods résolvent des noms.

### T16 — Inspecter un conteneur avec `crictl`
```bash
# 1) Retrouver l'ID du conteneur probe-httpd sur cp1
CID=$(sudo crictl ps --name probe-httpd -q | head -1)
echo "$CID"

# 2) ID + type de runtime dans container-info.txt
{
  echo "container-id: $CID"
  sudo crictl inspect "$CID" | grep -i runtimeType   # ex. "runtimeType": "io.containerd.runc.v2"
} > /opt/exam-03/container-info.txt

# (variante jq)
# sudo crictl inspect "$CID" | jq '.info.runtimeType'

# 3) Logs du conteneur
sudo crictl logs "$CID" > /opt/exam-03/container.log 2>&1
```

> Points clés testés :
> - `crictl` parle **directement au runtime** (containerd) via le socket CRI : indispensable quand l'API Kubernetes ne répond plus ou pour voir des conteneurs qui ne sont pas des Pods (kubelet, pause…).
> - `crictl ps` ≠ `kubectl get pods` : on manipule des **conteneurs** (ID de sandbox/app), pas des objets Pod. Le champ `info.runtimeType` confirme le runtime bas niveau (`io.containerd.runc.v2`).
> - `crictl logs <id>` lit les logs au niveau runtime, là où `kubectl logs` passe par l'API server.

### T12 — HTTPRoute (Gateway API)
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: route-splitter
  namespace: project-edge
spec:
  parentRefs:
  - name: edge-gw                 # rattachement au Gateway existant
  rules:
  - matches:                       # /web -> web-svc
    - path:
        type: PathPrefix
        value: /web
    backendRefs:
    - name: web-svc
      port: 80
  - matches:                       # /svc -> api-svc
    - path:
        type: PathPrefix
        value: /svc
    backendRefs:
    - name: api-svc
      port: 80
  - matches:                       # /shop + X-Tier: premium (ET logique) -> premium-svc
    - path:
        type: PathPrefix
        value: /shop
      headers:
      - name: X-Tier
        value: premium
    backendRefs:
    - name: premium-svc
      port: 80
  - matches:                       # /shop catch-all (sinon) -> standard-svc
    - path:
        type: PathPrefix
        value: /shop
    backendRefs:
    - name: standard-svc
      port: 80
EOF
```

> Points clés testés :
> - **Gateway API** sépare les rôles : `GatewayClass`/`Gateway` (infra, fournis) vs `HTTPRoute` (routage applicatif, à ta charge) — là où `Ingress` mélangeait tout.
> - Le lien route→gateway se fait par `parentRefs`, **pas** par une annotation de classe.
> - Un `match` qui liste à la fois `path` **et** `headers` applique un **ET logique** : les deux conditions doivent être vraies. Les séparer en deux `matches` donnerait un **OU** (piège classique).
> - L'**ordre des règles compte** : la règle `/shop` + en-tête doit précéder le catch-all `/shop`, sinon toutes les requêtes `/shop` partent vers le backend par défaut.
> - Le routage conditionnel par en-tête (`headers`) n'est pas exprimable nativement avec `Ingress`.
> - Sans contrôleur Gateway installé, l'objet est **valide** mais non programmé (pas d'adresse) — l'exam valide la **spécification**.

### T15 — CoreDNS : domaine personnalisé `cka.local`
```bash
# 1) Sauvegarde AVANT toute modif
kubectl -n kube-system get cm coredns -o yaml > /opt/exam-03/coredns_original.yaml

# 2) Éditer le Corefile : ajouter cka.local sur la ligne du plugin kubernetes
kubectl -n kube-system edit cm coredns
#   kubernetes cluster.local cka.local in-addr.arpa ip6.arpa {
#       ...
#   }

# 3) Recharger CoreDNS
kubectl -n kube-system rollout restart deployment coredns
```

> Points clés testés :
> - Le plugin `kubernetes` accepte **plusieurs zones** : ajouter `cka.local` à côté de `cluster.local` fait résoudre les *Services* sous les deux domaines.
> - **Toujours sauvegarder** la ConfigMap avant édition : une faute de Corefile casse le DNS de tout le cluster.
> - Le plugin `reload` recharge automatiquement le Corefile (≈ 30 s–2 min) ; `rollout restart` force la prise en compte immédiate.

### T17 — Introspection etcd
```bash
# etcd tourne en static pod : ses drapeaux sont dans le manifeste
sudo grep -E 'key-file|cert-file|client-cert-auth' /etc/kubernetes/manifests/etcd.yaml

# Expiration du certificat serveur
sudo openssl x509 -noout -enddate -in /etc/kubernetes/pki/etcd/server.crt

# Écrire les 3 informations (format libre)
cat > /opt/exam-03/etcd-info.txt <<'EOF'
server-private-key: /etc/kubernetes/pki/etcd/server.key
server-cert-expiration: Aug 10 12:52:19 2027 GMT
client-cert-auth: true (activée)
EOF
```

> Points clés testés :
> - Les composants du control plane sont des **static Pods** : la vérité de leur configuration est dans `/etc/kubernetes/manifests/*.yaml`, pas dans l'API.
> - `--client-cert-auth=true` → etcd exige un **certificat client** valide (mTLS) ; c'est ce qui protège l'accès à la base.
> - `openssl x509 -enddate` et `kubeadm certs check-expiration` doivent donner la **même** date pour le cert etcd serveur.

### T18 — Règles iptables d'un Service (kube-proxy)
```bash
# 1) Pod + Service ClusterIP 3100 -> 80
kubectl -n project-proxy run p-proxy --image=nginx:1-alpine
kubectl -n project-proxy expose pod p-proxy --name=proxy-svc --port=3100 --target-port=80

# 2) ClusterIP attribué
CIP=$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.clusterIP}'); echo "$CIP"

# 3) Règles iptables générées par kube-proxy (table nat)
sudo iptables-save -t nat | grep proxy-svc > /opt/exam-03/iptables.txt
#   (équivalent : sudo iptables-save -t nat | grep "$CIP")
cat /opt/exam-03/iptables.txt
```

Démonstration (facultatif) : supprimer le Service retire ses règles.
```bash
kubectl -n project-proxy delete svc proxy-svc
sudo iptables-save -t nat | grep proxy-svc   # → plus aucune ligne
```

> Points clés testés :
> - kube-proxy en mode **iptables** programme la table `nat` : `KUBE-SERVICES` → `KUBE-SVC-*` (un par Service) → `KUBE-SEP-*` (un par endpoint/Pod).
> - Le **ClusterIP** n'est pas une interface réelle : c'est une règle **DNAT** qui réécrit la destination vers un Pod.
> - kube-proxy **réconcilie en continu** : créer/supprimer un Service ajoute/retire immédiatement ses chaînes.

### T19 — Ajouter une plage d'IP de Services (API ServiceCIDR)
```bash
# 0) Pod cible
kubectl -n project-range run range-probe --image=httpd:2-alpine

# 1) Premier Service — IP de la plage par défaut (ServiceCIDR « kubernetes »)
kubectl -n project-range expose pod range-probe --name=range-svc --port=80

# 2) Nouvelle plage d'IP de Services, à chaud (sans redémarrer kube-apiserver)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: extra-range
spec:
  cidrs:
  - 11.96.0.0/12
EOF

# 3) Second Service avec une clusterIP issue de la nouvelle plage
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: range-svc2
  namespace: project-range
spec:
  clusterIP: 11.96.0.10
  selector:
    run: range-probe
  ports:
  - port: 80
    targetPort: 80
EOF

kubectl get servicecidr
kubectl -n project-range get svc -o wide
kubectl get ipaddress | grep 11.96      # l'IP allouée apparaît ici
```

> Points clés testés :
> - L'API **ServiceCIDR / IPAddress** (GA) permet d'ajouter des plages d'IP de Services **à chaud**, sans éditer `--service-cluster-ip-range` ni redémarrer `kube-apiserver`.
> - Chaque IP de Service alloue un objet **IPAddress** ; `kubectl get ipaddress` liste les IP prises et leur Service parent.
> - La plage par défaut est le ServiceCIDR nommé `kubernetes` ; son champ `spec.cidrs` est **immuable** (l'API rejette toute modification : `field is immutable`). Même si un énoncé dit « changer » la plage, la seule opération possible est d'**ajouter** un ServiceCIDR complémentaire.
> - À l'ancienne (hors CKA moderne), changer la plage imposait de modifier le drapeau du kube-apiserver et de **recréer** les Services — opération disruptive que l'API ServiceCIDR remplace.

---

## 🔁 Recommencer à zéro
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/setup.sh"   # ré-initialise l'état de départ
```
