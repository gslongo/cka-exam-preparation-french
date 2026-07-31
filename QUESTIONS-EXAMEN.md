# 📝 Questions à haute probabilité d'examen CKA

> Fichier vivant — l'agent ajoute des questions au fil de la session.
> Chaque entrée : **énoncé type** · **solution** · **logique** (le *pourquoi*, pas juste le *comment*).
> Basé sur le curriculum CKA v1.35 (exam actuel) et les patterns killer.sh / retours candidats.
> **Trié par probabilité d'apparition décroissante.**

_Dernière mise à jour : 2026-07-27_

**Rappel exam** : 2 h · ~15-20 tâches · passage **66 %** · toujours `kubectl config use-context <ctx>` avant chaque tâche.

---

## 🗂️ Index (du plus probable au moins probable)

| # | Question | Domaine | Fréquence |
|---|---|---|---|
| Q1 | Sauvegarder + restaurer etcd | 01 | ⭐⭐⭐ quasi garantie |
| Q2 | Upgrade kubeadm (CP + worker) | 01 | ⭐⭐⭐ |
| Q3 | Réparer un static Pod cassé | 01/05 | ⭐⭐⭐ |
| Q4 | Node NotReady → diagnostiquer | 05 | ⭐⭐⭐ |
| Q5 | Pod Pending → diagnostiquer le scheduling | 05/02 | ⭐⭐⭐ |
| Q6 | Créer une NetworkPolicy | 03 | ⭐⭐⭐ |
| Q7 | Scheduling : taint + toleration + nodeSelector | 02 | ⭐⭐⭐ |
| Q8 | RBAC : Role + RoleBinding + ServiceAccount | 01 | ⭐⭐ |
| Q9 | Exposer un Deployment (Service) | 03 | ⭐⭐ |
| Q10 | Rolling update + rollback d'un Deployment | 02 | ⭐⭐ |
| Q11 | ConfigMap / Secret → variables & volume | 02 | ⭐⭐ |
| Q12 | Sidecar / Pod multi-conteneurs | 02 | ⭐⭐ |
| Q13 | DaemonSet | 02 | ⭐⭐ |
| Q14 | PVC + Pod qui le monte | 04 | ⭐⭐ |
| Q15 | PV + StorageClass + PVC | 04 | ⭐⭐ |
| Q16 | Ingress | 03 | ⭐⭐ |
| Q17 | DNS / connectivité Service (debug) | 03/05 | ⭐⭐ |
| Q18 | Approuver un CertificateSigningRequest | 01 | ⭐⭐ |
| Q19 | Grow the cluster : `kubeadm join` (token expiré) | 01 | ⭐⭐ |

---

## Q1 · etcd — snapshot save + restore ⭐⭐⭐

**Énoncé type**
> Backup the etcd cluster to `/opt/etcd-backup.db`. Then restore it from `/opt/etcd-backup.db`.

**Solution**
```bash
# --- (Astuce) Valider les certs/endpoint AVANT le snapshot ---
# Si member list répond, tes flags sont bons → enchaîne le save.
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# --- BACKUP ---
ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Vérifier (inspection d'un fichier → etcdutl)
etcdutl --write-out=table snapshot status /opt/etcd-backup.db

# --- RESTORE (etcd 3.6+ : etcdutl, opération LOCALE, pas de certs/endpoints) ---
etcdutl snapshot restore /opt/etcd-backup.db \
  --data-dir=/var/lib/etcd-restore

# Si etcdutl absent de l'hôte, exec dans le Pod etcd (le binaire y est) :
#   kubectl -n kube-system exec etcd-cp -- etcdutl snapshot restore ...

# Puis éditer /etc/kubernetes/manifests/etcd.yaml :
#   volume "etcd-data" → hostPath.path: /var/lib/etcd-restore
# Le kubelet redémarre le static Pod etcd automatiquement.
```

> ⚠️ **Restore propre (recommandé par la doc)** : ne restaure **jamais** etcd avec l'apiserver actif → risque de données incohérentes. Procédure kubeadm (static pods) :
> ```bash
> # 1. Stopper apiserver + etcd en sortant leurs manifests (le kubelet tue les Pods)
> sudo mv /etc/kubernetes/manifests/{kube-apiserver,etcd}.yaml /tmp/
> # 2. Restaurer vers un nouveau data-dir
> sudo etcdutl snapshot restore /opt/etcd-backup.db --data-dir=/var/lib/etcd-restore
> # 3. Repointer etcd.yaml : hostPath du volume etcd-data → /var/lib/etcd-restore
> sudo vim /tmp/etcd.yaml
> # 4. Remettre les manifests → le kubelet recrée etcd (restauré) puis apiserver
> sudo mv /tmp/{etcd,kube-apiserver}.yaml /etc/kubernetes/manifests/
> ```
> La doc conseille aussi de **redémarrer** `kube-scheduler`, `kube-controller-manager`, `kubelet` pour purger tout état obsolète (ils perdent le **leader lock** et se relancent seuls).

**Logique**
- `ETCDCTL_API=3` = force l'API v3 (celle des commandes `snapshot`/`member list`). Souvent le défaut sur etcd récent, mais on le met **par habitude** (zéro risque).
- **Astuce** : `member list` est le test le moins destructif pour valider certs + endpoint. S'il répond, le `snapshot save` passera → évite de découvrir un `context deadline exceeded` sur la vraie commande.
- etcd = TLS mutuel → sans les 3 certs, `context deadline exceeded`. Les chemins se **lisent dans** `/etc/kubernetes/manifests/etcd.yaml` (ne pas mémoriser).
- Le **restore** crée un **nouveau data-dir** ; il faut **repointer le manifest** pour qu'etcd l'utilise.
- ⚠️ **etcd 3.6 (CKA v1.35)** : `etcdctl snapshot restore` est **retiré** → utiliser **`etcdutl snapshot restore`**. Règle : **live = `etcdctl`** (`snapshot save`, avec certs/endpoint), **fichier = `etcdutl`** (`snapshot status` + `snapshot restore`, hors-ligne, **ni endpoints ni certs**). _(Source : doc kubernetes.io ; LFS258 diffère le restore et ne couvre pas `etcdutl`.)_
- Si l'**URL/IP d'etcd change** au restore, il faut réaligner l'apiserver (`--etcd-servers=...` dans son manifest). Dans notre cas mono-nœud sur `127.0.0.1`, rien à changer — on **repointe juste le data-dir**.
- L'apiserver étant un static pod qui parle à etcd, il "suit" automatiquement au redémarrage du Pod etcd.
- **Un snapshot ne suffit pas** pour reconstruire un cluster mort : sauvegarde aussi `kubeadm-config.yaml` et **`/etc/kubernetes/pki/etcd/`** (les certs). Copie le tout **hors du node** (autre machine). En prod : **cronjob** régulier.
- **HA** : pas de restore — on **supprime/remplace** le node de control plane, les autres membres etcd resynchronisent. Le restore ne sert que sur un etcd **mono-nœud** (et la DB doit être **à l'arrêt/hors usage**).

**Alternative — `etcdctl` absent de l'hôte : exec dans le Pod etcd**
> Sur certains envs (LF hosted, parfois l'exam), `etcdctl` n'est pas installé sur le node. On l'appelle depuis le conteneur etcd (le binaire y est toujours) :
```bash
# <TAB> complète : le nom du Pod = etcd-<nodename> (ex: etcd-cp)
kubectl -n kube-system exec etcd-cp -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --endpoints=https://127.0.0.1:2379 \
  endpoint health          # → "is healthy"

# member list en table :  ... member list -w table
```
> 💡 **Astuce contournement** : sauvegarde dans `/var/lib/etcd/` (le **data-dir = hostPath** monté dans le Pod) → le `.db` apparaît **directement sur le node**, pas besoin de `kubectl cp`. Vérifie côté hôte : `sudo ls -l /var/lib/etcd/`. Les certs sont déjà montés dans le Pod aux **mêmes chemins**. `ETCDCTL_API=3` inutile ici (etcd du Pod est déjà en v3).

---

## Q2 · Upgrade kubeadm ⭐⭐⭐

**Énoncé type**
> Upgrade the control plane node from 1.34.x to 1.35.x. Do not upgrade worker nodes.

**Solution (control plane primaire) — ordre `d→f→b→e→c→a`**

**Étape 0 (souvent oubliée) — le dépôt apt est *par minor version*** :
```bash
# pkgs.k8s.io a un chemin /v1.34/ , /v1.35/ ... → il faut le bumper AVANT tout
sudo sed -i 's/1.34/1.35/' /etc/apt/sources.list.d/kubernetes.list
sudo apt update
apt-cache madison kubeadm        # → trouver la version patch exacte (ex: 1.35.2-1.1)
```

```bash
apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.35.x-* && apt-mark hold kubeadm  # d
kubeadm upgrade plan                                                                                        # f
kubeadm upgrade apply v1.35.x                                                                               # b
kubectl drain <cp> --ignore-daemonsets                                                                     # e
apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.35.x-* kubectl=1.35.x-* && apt-mark hold kubelet kubectl && systemctl daemon-reload && systemctl restart kubelet  # c
kubectl uncordon <cp>                                                                                       # a
```

**Logique**
- **Dépôt par minor** : sans le `sed` sur `kubernetes.list`, `apt` reste bloqué en 1.34 et `install kubeadm=1.35.x` échoue (`Version not found`). `apt-cache madison kubeadm` donne les patchs dispo.
- **kubeadm binaire en 1er** : `upgrade plan/apply` a besoin du nouveau kubeadm.
- **drain APRÈS `apply`** : l'apiserver est un static Pod → tourne même node drainé ; le drain protège les workloads avant de toucher au **kubelet**.
- **Workers / CP additionnels** : `kubeadm upgrade node` (pas `apply`, pas `plan`).
- Skew : une seule minor à la fois (1.34→1.35).

---

## Q3 · Réparer un static Pod cassé ⭐⭐⭐

**Énoncé type**
> The kube-apiserver on the control plane is down. Fix it. (souvent : un flag erroné dans le manifest)

**Solution**
```bash
# L'apiserver est down → kubectl ne répond pas. Passer par le runtime :
sudo crictl ps -a | grep apiserver          # voir l'état / crash
sudo crictl logs <container-id>              # lire l'erreur

# Éditer le manifest fautif :
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml
# corriger le flag / indentation / port erroné
# → sauvegarder ; le kubelet recrée le Pod automatiquement (~30 s)

kubectl get pods -n kube-system              # revérifier une fois l'API up
```

**Logique**
- Si l'apiserver est mort, **`kubectl` est inutilisable** → on debug via `crictl` (parle direct à containerd).
- Static Pod = **pas de `kubectl delete`** ; toute correction passe par le **fichier** dans `manifests/`.
- Erreurs fréquentes injectées : mauvais `--etcd-servers`, port, chemin de cert, indentation YAML.

---

## Q4 · Node NotReady — diagnostic ⭐⭐⭐

**Énoncé type**
> Worker node `w1` is NotReady. Investigate and fix.

**Solution**
```bash
kubectl get nodes
kubectl describe node w1 | grep -A10 Conditions   # indice (Kubelet, NetworkUnavailable...)

# SSH sur le node :
ssh w1
systemctl status kubelet                          # souvent inactive/failed
journalctl -u kubelet -e --no-pager | tail -40    # cause racine

# Causes fréquentes + fix :
#  - kubelet arrêté        → systemctl enable --now kubelet
#  - swap réactivé         → swapoff -a
#  - containerd down       → systemctl restart containerd
#  - certif/kubeconfig KO  → vérifier /etc/kubernetes/kubelet.conf
```

**Logique**
- `NotReady` = le kubelet ne poste plus son heartbeat. On remonte : node → kubelet → runtime.
- **Heartbeat = NodeLease** (objet `Lease` dans `kube-node-lease`, renouvelé ~10 s) + `NodeStatus` (lourd, ~1 min). Le **node-controller** passe le node `NotReady` si le lease n'est pas renouvelé sous `--node-monitor-grace-period` (~40 s). Kubelet mort = plus de lease = NotReady.
- `journalctl -u kubelet` donne quasi toujours la cause exacte.
- Réflexe **SRC** utile ici aussi (swap/réseau/CRI).

---

## Q5 · Pod Pending — diagnostiquer le scheduling ⭐⭐⭐

**Énoncé type**
> Pod `web` stays `Pending`. Find out why and make it schedulable.

**Solution**
```bash
kubectl get pod web -o wide
kubectl describe pod web | grep -A15 Events   # message du scheduler = LA clé

# Causes typiques + fix :
#  - "Insufficient cpu/memory"        → baisser requests ou libérer un node
#  - "node(s) had untolerated taint"  → ajouter une toleration (voir Q7)
#  - "didn't match node selector"     → corriger nodeSelector / labels
#  - "no nodes available" / cordon    → kubectl uncordon <node>
#  - PVC Pending (WaitForFirstConsumer)→ créer le Pod/SC adéquat
```

**Logique**
- `Pending` = **le scheduler n'a trouvé aucun node**. Le message dans `Events` (`describe`) donne toujours la raison exacte.
- Ne jamais deviner : lire l'événement du `default-scheduler`.
- Différent de `ContainerCreating` (image/volume) ou `CrashLoopBackOff` (appli qui crash).

---

## Q6 · NetworkPolicy ⭐⭐⭐

**Énoncé type**
> In namespace `prod`, allow only Pods labeled `role=frontend` to reach Pods labeled `app=api` on TCP 8080. Deny everything else.

**Solution**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend
      ports:
        - protocol: TCP
          port: 8080
```

**Logique**
- `podSelector` (haut) = Pods **protégés** (les `api`).
- Dès qu'une NetPol sélectionne un Pod, tout ce qui n'est **pas** explicitement autorisé est **bloqué** (deny par défaut sur ce type).
- `from` liste les sources autorisées. Attention à la différence `podSelector` vs `namespaceSelector`.
- **Requiert un CNI qui applique les NetPol** (Calico/Cilium ; PAS Flannel seul).

---

## Q7 · Scheduling — taint + toleration + nodeSelector ⭐⭐⭐

**Énoncé type**
> Taint node `w1` with `gpu=true:NoSchedule`. Then schedule a Pod `cuda` there (and only there).

**Solution**
```bash
# Poser le taint
kubectl taint nodes w1 gpu=true:NoSchedule

# Labéliser le node pour cibler avec nodeSelector
kubectl label node w1 gpu=true
```
```yaml
apiVersion: v1
kind: Pod
metadata: { name: cuda }
spec:
  nodeSelector:            # → force le placement sur w1
    gpu: "true"
  tolerations:            # → autorise à passer le taint
    - key: gpu
      operator: Equal
      value: "true"
      effect: NoSchedule
  containers:
    - name: c
      image: nginx
```

**Logique**
- **Taint (sur le node)** repousse : `NoSchedule` bloque tout Pod sans toleration. **Toleration (sur le Pod)** = laissez-passer, mais **n'attire pas**.
- Pour *forcer* le Pod sur ce node précis, il faut **en plus** un `nodeSelector`/`nodeAffinity`.
- Vérifier : `kubectl describe node w1 | grep Taints`.

---

## Q8 · RBAC — Role + RoleBinding + SA ⭐⭐

**Énoncé type**
> Create a ServiceAccount `deployer` in `dev` that can `get/list/create` Pods in `dev` only.

**Solution**
```bash
kubectl create serviceaccount deployer -n dev
kubectl create role pod-manager -n dev \
  --verb=get,list,create --resource=pods
kubectl create rolebinding deployer-binding -n dev \
  --role=pod-manager --serviceaccount=dev:deployer

# Vérifier :
kubectl auth can-i create pods -n dev --as=system:serviceaccount:dev:deployer   # yes
kubectl auth can-i create pods -n prod --as=system:serviceaccount:dev:deployer  # no
```

**Logique**
- `Role` + `RoleBinding` = portée **namespace**. `ClusterRole` + `ClusterRoleBinding` = **cluster-wide**.
- `kubectl auth can-i ... --as=` = LA commande de vérification (et de debug RBAC).
- Nom d'un SA en tant que sujet : `system:serviceaccount:<ns>:<name>`.
- **Appliquer un manifest RBAC** : `kubectl auth reconcile -f rbac.yaml` (mieux qu'`apply` pour du RBAC : réconcilie règles/bindings, gère les agrégations de ClusterRoles). `apply` reste accepté à l'exam.

---

## Q9 · Exposer un Deployment ⭐⭐

**Énoncé type**
> Expose deployment `web` on port 80 as a NodePort service.

**Solution**
```bash
kubectl expose deployment web --port=80 --target-port=8080 --type=NodePort
kubectl get svc web           # noter le nodePort (30000-32767)
kubectl get endpoints web     # vérifier que les Pods sont bien backend
```

**Logique**
- `--port` = port du Service (ClusterIP) ; `--target-port` = port du conteneur.
- NodePort ouvre le port sur **TOUS les nodes** (kube-proxy), pas seulement ceux hébergeant un Pod.
- `endpoints` vides = le selector du Service ne matche aucun Pod → bug de labels.

---

## Q10 · Rolling update + rollback ⭐⭐

**Énoncé type**
> Update deployment `web` to image `nginx:1.27`, then roll back after a failed rollout.

**Solution**
```bash
kubectl set image deployment/web web=nginx:1.27      # déclenche le rolling update
kubectl rollout status deployment/web                # suivre le déploiement
kubectl rollout history deployment/web               # voir les révisions

# Rollback :
kubectl rollout undo deployment/web                  # revient à la révision précédente
kubectl rollout undo deployment/web --to-revision=2  # ou une révision précise
```

**Logique**
- Un Deployment gère les révisions via ses ReplicaSets ; `undo` re-scale l'ancien RS.
- `rollout status` = bloque tant que le rollout n'est pas fini → utile pour détecter un blocage.
- `maxSurge` / `maxUnavailable` contrôlent le rythme (dans `spec.strategy.rollingUpdate`).

---

## Q11 · ConfigMap / Secret → env & volume ⭐⭐

**Énoncé type**
> Create a ConfigMap `app-config` (key `MODE=prod`) and a Secret `db-cred` (`PASSWORD=s3cret`). Inject both into a Pod.

**Solution**
```bash
kubectl create configmap app-config --from-literal=MODE=prod
kubectl create secret generic db-cred --from-literal=PASSWORD=s3cret
```
```yaml
    env:
      - name: MODE
        valueFrom:
          configMapKeyRef: { name: app-config, key: MODE }
      - name: PASSWORD
        valueFrom:
          secretKeyRef: { name: db-cred, key: PASSWORD }
    # ou monter en volume :
    volumeMounts:
      - name: cfg
        mountPath: /etc/config
  volumes:
    - name: cfg
      configMap: { name: app-config }
```

**Logique**
- 2 modes d'injection : **variables d'env** (`valueFrom`) ou **volume** (fichier par clé).
- Secret = juste base64 (pas chiffré par défaut) → même structure que ConfigMap mais `secretKeyRef`.
- `envFrom` injecte **toutes** les clés d'un coup.

---

## Q12 · Sidecar / Pod multi-conteneurs ⭐⭐

**Énoncé type**
> Add a sidecar container to Pod `web` that tails `/var/log/app.log` via a shared volume.

**Solution**
```yaml
spec:
  containers:
    - name: app
      image: myapp
      volumeMounts:
        - { name: logs, mountPath: /var/log }
    - name: sidecar                       # conteneur secondaire
      image: busybox
      args: [ /bin/sh, -c, 'tail -f /var/log/app.log' ]
      volumeMounts:
        - { name: logs, mountPath: /var/log }
  volumes:
    - name: logs
      emptyDir: {}
```

**Logique**
- Les conteneurs d'un même Pod partagent **réseau (localhost)** et **volumes** → le sidecar lit les logs via un `emptyDir` commun.
- Un Pod ne peut **pas** être édité pour ajouter un conteneur à chaud → il faut **recréer** (`kubectl replace --force` ou delete/apply).
- Sidecar « natif » = `initContainers` avec `restartPolicy: Always` (K8s récent).

---

## Q13 · DaemonSet ⭐⭐

**Énoncé type**
> Deploy a DaemonSet `node-agent` (image `fluentd`) running on every node, including control plane.

**Solution**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent }
spec:
  selector:
    matchLabels: { app: node-agent }
  template:
    metadata:
      labels: { app: node-agent }
    spec:
      tolerations:                        # pour tourner aussi sur le control plane
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule
      containers:
        - name: agent
          image: fluentd
```

**Logique**
- DaemonSet = **1 Pod par node** (pas de `replicas`) ; le scheduler y place automatiquement un Pod sur chaque node éligible.
- Pour couvrir le **control plane**, il faut **tolérer son taint** `node-role.kubernetes.io/control-plane:NoSchedule`.
- Usage type : logs, monitoring, CNI, kube-proxy.

---

## Q14 · PVC + Pod qui le monte ⭐⭐

**Énoncé type**
> Create a PVC `data` (1Gi, RWO) and a Pod that mounts it at `/data`.

**Solution**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ "ReadWriteOnce" ]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata: { name: app }
spec:
  containers:
    - name: c
      image: nginx
      volumeMounts:
        - name: v
          mountPath: /data
  volumes:
    - name: v
      persistentVolumeClaim:
        claimName: data
```

**Logique**
- PVC minimal = `accessModes` + `resources.requests.storage`. StorageClass default assumée.
- Si PVC reste `Pending` : `kubectl describe pvc` → souvent `WaitForFirstConsumer` (se débloque quand le Pod est schedulé) ou pas de SC default.
- Le Pod référence le PVC par `claimName`, pas le PV directement.

---

## Q15 · PV + StorageClass + PVC ⭐⭐

**Énoncé type**
> Create a hostPath PV `pv-1` (2Gi, RWO) and a PVC that binds to it exactly.

**Solution**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-1 }
spec:
  capacity: { storage: 2Gi }
  accessModes: [ "ReadWriteOnce" ]
  storageClassName: manual
  hostPath: { path: /mnt/data }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-1 }
spec:
  accessModes: [ "ReadWriteOnce" ]
  storageClassName: manual       # doit matcher le PV
  resources:
    requests:
      storage: 2Gi
```

**Logique**
- Le binding PV↔PVC exige : **accessModes compatibles**, **capacité PVC ≤ PV**, et **même `storageClassName`**.
- `storageClassName: ""` (vide) = pas de provisioning dynamique → force le binding manuel à un PV existant.
- Vérifier : `kubectl get pv,pvc` → statut `Bound`.

---

## Q16 · Ingress ⭐⭐

**Énoncé type**
> Route `http://<ingress>/app` to service `web:80` via an Ingress named `web-ing`.

**Solution**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ing
spec:
  rules:
    - http:
        paths:
          - path: /app
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

**Logique**
- L'Ingress est juste une **règle** ; il faut un **Ingress Controller** déployé (nginx, etc.) pour qu'elle serve à quelque chose.
- `pathType: Prefix` est le plus courant ; `Exact` matche à l'identique.
- Le `backend.service` doit exister et avoir des endpoints (vérifier `kubectl get endpoints web`).

---

## Q17 · DNS / connectivité Service — debug ⭐⭐

**Énoncé type**
> Pods can't reach service `web` by name. Diagnose the DNS / Service issue.

**Solution**
```bash
kubectl get svc web -o wide
kubectl get endpoints web                 # vide ? → selector KO / pas de Pod ready

# Depuis un Pod de test :
kubectl run tmp --image=busybox -it --rm -- sh
  nslookup web                            # résout ? sinon problème DNS
  nslookup web.default.svc.cluster.local
  wget -qO- web:80

# Vérifier CoreDNS :
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Logique**
- FQDN d'un Service = `<svc>.<ns>.svc.cluster.local`. Résolu par **CoreDNS**.
- `endpoints` vides = le Service ne pointe vers aucun Pod → problème de **selector/labels** ou Pods non `Ready`.
- Si `nslookup` échoue partout → CoreDNS down ou config kubelet `clusterDNS` erronée.

---

## Q18 · Approuver un CertificateSigningRequest ⭐⭐

**Énoncé type**
> A new user submitted a CSR named `john`. Approve it and verify.

**Solution**
```bash
kubectl get csr                       # voir l'état Pending
kubectl certificate approve john      # approuver
kubectl get csr john                  # état → Approved,Issued

# Récupérer le certificat signé :
kubectl get csr john -o jsonpath='{.status.certificate}' | base64 -d > john.crt
```

**Logique**
- Un CSR `Pending` attend une **décision manuelle** de l'admin (`approve` / `deny`).
- Le certificat n'est **émis** qu'après approbation, puis lisible dans `.status.certificate` (base64).
- Sert à créer des identités utilisateur (à combiner avec un RoleBinding — cf. Q8).

---

## Q19 · Grow the cluster — `kubeadm join` (token expiré) ⭐⭐

**Énoncé type**
> A new worker node must join the cluster. The old join token has expired. Generate a fresh join command and add the node.

**Solution**
```bash
# --- Sur le CONTROL PLANE : produire une commande de join fraîche ---
kubeadm token create --print-join-command
# → sortie type :
#   kubeadm join 192.168.56.10:6443 --token <tok> \
#     --discovery-token-ca-cert-hash sha256:<hash>

# --- Sur le WORKER : exécuter la commande obtenue ---
sudo kubeadm join 192.168.56.10:6443 --token <tok> \
  --discovery-token-ca-cert-hash sha256:<hash>

# --- Vérifier depuis le CONTROL PLANE ---
kubectl get nodes            # le node passe Ready (après démarrage du CNI)
```

**Logique**
- Un **token bootstrap expire après 24 h** → si le lab dit « token expiré », le réflexe est `kubeadm token create --print-join-command` (régénère token **+** hash du CA en une commande).
- `kubeadm join` s'exécute **sur le worker**, PAS sur le control plane.
- Le node peut rester **NotReady** quelques secondes le temps que le CNI démarre → normal, attendre.
- Prérequis (déjà en place à l'exam en général) : containerd + kubelet installés, swap off, modules kernel.

---

_Ajoute une question ici en disant : « ajoute la question sur <sujet> »._
