# ✅ CKA — Examen blanc n°2 (avancé) · SOLUTIONS

> **N'ouvre ce fichier qu'après ta tentative.** Chaque solution correspond exactement aux critères de `grade.sh`.
> Toutes les commandes sont à lancer depuis `cp1` (`vagrant ssh cp1`), **sauf T3** (sur `w1`).

---

## 🏛️ Cluster Architecture

### T1 — RBAC cluster-scoped (`platform`)
```bash
kubectl -n platform create sa ci-bot

# ClusterRole limité aux deployments (pas de nodes → droits volontairement bornés)
kubectl create clusterrole deploy-admin \
  --verb=get,list,watch,create,update,patch \
  --resource=deployments.apps

kubectl create clusterrolebinding ci-bot-deploy \
  --clusterrole=deploy-admin \
  --serviceaccount=platform:ci-bot

# Vérif
kubectl auth can-i create deployments --as=system:serviceaccount:platform:ci-bot -n default   # yes
kubectl auth can-i delete nodes       --as=system:serviceaccount:platform:ci-bot               # no
```

### T2 — Upgrade du control plane 1.34 → 1.35 (sur `cp1`) · ⚠️ à faire en DERNIER
> **Irréversible** : une fois `cp1` en 1.35, `setup.sh` ne peut pas revenir en arrière → redeploy nécessaire pour rejouer l'examen.
```bash
# 1) Basculer le dépôt apt de v1.34 → v1.35 (clé + liste)
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo sed -i 's#v1\.34/deb#v1.35/deb#' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

# 2) Installer kubeadm 1.35 (le paquet est « hold » → unhold d'abord)
sudo apt-cache madison kubeadm | head           # repérer le patch dispo, ex : 1.35.0-1.1
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm='1.35.0-1.1'     # adapter au patch listé
sudo apt-mark hold kubeadm
kubeadm version

# 3) Planifier puis appliquer l'upgrade du control plane
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.35.0 -y            # adapter au patch exact

# 4) Drainer cp1, upgrader kubelet + kubectl, redémarrer, uncordon
kubectl drain cp1 --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet='1.35.0-1.1' kubectl='1.35.0-1.1'
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon cp1

# 5) Vérif
kubectl get node cp1        # STATUS Ready, VERSION v1.35.x
```
> Pour upgrader aussi un worker (`w1`/`w2`) : même bascule de dépôt **sur le node**, puis `sudo kubeadm upgrade node`, `kubectl drain <node> --ignore-daemonsets` (depuis cp1), upgrade de `kubelet`, `systemctl restart kubelet`, `kubectl uncordon <node>`. La correction ne note que `cp1`.

### T3 — Static Pod avec label `role=cache` (sur `w1`)
```bash
vagrant ssh w1          # depuis l'hôte
sudo tee /etc/kubernetes/manifests/static-web.yaml >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  labels:
    role: cache
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    ports: [{ containerPort: 80 }]
EOF
# Le kubelet le détecte seul → le mirror pod "static-web-w1" apparaît côté API.
```
> Le static pod n'est pas soumis au scheduler : le taint de `w1` (T7) ne le gêne pas.

### T4 — Scheduling manuel sur `w2` (`apps`)
```bash
kubectl -n apps apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: pinned, namespace: apps }
spec:
  nodeName: w2        # on court-circuite le scheduler
  containers:
  - { name: web, image: nginx:1.29-alpine }
EOF
```

---

## 📦 Workloads & Scheduling

### T5 — Deployment `api` + stratégie de rollout (`apps`)
```bash
kubectl -n apps apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: api, namespace: apps }
spec:
  replicas: 3
  selector: { matchLabels: { app: api } }
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 0, maxSurge: 1 }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
      - name: web
        image: nginx:1.29-alpine
        ports: [{ containerPort: 80 }]
        resources:
          requests: { cpu: 50m, memory: 32Mi }
EOF
kubectl -n apps rollout status deploy/api
```
> Les 3 réplicas se placent sur `w2` (cp1 et `w1` sont taintés).

### T6 — Secret → variable d'env (`apps`)
```bash
kubectl -n apps create secret generic app-secret --from-literal=TOKEN=s3cr3t

kubectl -n apps apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: secret-pod, namespace: apps }
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: ["sh","-c","sleep 100000"]
    env:
    - name: TOKEN
      valueFrom:
        secretKeyRef: { name: app-secret, key: TOKEN }
EOF
```

### T7 — Taint + toleration (`apps`)
```bash
kubectl taint node w1 dedicated=cka:NoSchedule

kubectl -n apps apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: tolerant, namespace: apps }
spec:
  nodeSelector: { kubernetes.io/hostname: w1 }   # cible w1
  tolerations:
  - key: dedicated
    operator: Equal
    value: cka
    effect: NoSchedule
  containers:
  - { name: web, image: nginx:1.29-alpine }
EOF
```
> Sans la toleration, le pod resterait `Pending` (w1 repousse tout le reste).

---

## 🌐 Services & Networking

### T8 — Ingress `api-ing` (`apps`)
```bash
kubectl -n apps apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: api-ing, namespace: apps }
spec:
  rules:
  - host: api.cka.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-np
            port: { number: 80 }
EOF
kubectl -n apps get ingress api-ing
```
> Le lab n'a **pas** de contrôleur Ingress → l'Ingress n'obtiendra pas d'adresse et ne routera pas réellement ; `grade.sh` ne vérifie que la **définition** (host / path / backend `api-np:80`).

### T9 — NodePort `api-np` (`apps`)
```bash
kubectl -n apps expose deployment api --name=api-np --type=NodePort --port=80 --target-port=80
kubectl -n apps patch svc api-np -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30090}]}}'
kubectl -n apps get svc api-np             # NodePort 30090
```

### T10 — NetworkPolicy default-deny + allow (`secure`)
```bash
kubectl -n secure apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: secure }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-web-to-db, namespace: secure }
spec:
  podSelector: { matchLabels: { app: db } }
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: { matchLabels: { app: web } }
    ports: [{ port: 80, protocol: TCP }]
EOF

# Vérif
kubectl -n secure exec web     -- wget -T3 -qO- http://db >/dev/null && echo "web OK"
kubectl -n secure exec scanner -- wget -T3 -qO- http://db    # doit timeout
```

---

## 💾 Storage

### T11 — PV (Retain) + PVC (`storage`)
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-fast }
spec:
  capacity: { storage: 2Gi }
  accessModes: [ReadWriteOnce]
  storageClassName: fast
  persistentVolumeReclaimPolicy: Retain
  hostPath: { path: /mnt/data-02, type: DirectoryOrCreate }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast
  resources: { requests: { storage: 1Gi } }
EOF

kubectl -n storage get pvc data     # Bound → pv-fast
```

### T12 — Pod monté via `subPath` (`storage`)
```bash
kubectl -n storage apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: storage }
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
      subPath: html
  volumes:
  - name: data
    persistentVolumeClaim: { claimName: data }
EOF
```
> Piège : avec `subPath` sur un `hostPath`, le répertoire de base doit exister sur le node, sinon le montage échoue (`stat /mnt/data-02: no such file or directory` → pod en `CreateContainerConfigError`). D'où le `type: DirectoryOrCreate` du PV en T11, qui laisse le kubelet créer le dossier.

---

## 🔧 Troubleshooting

### T13 — readinessProbe sur le mauvais port (`trouble/frontend`)
Cause : la sonde interroge `:8080` alors que nginx écoute `:80`.
```bash
kubectl -n trouble patch deploy frontend --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]'
kubectl -n trouble rollout status deploy/frontend
```

### T14 — Résolution DNS cassée (`trouble/dns-check`)
Cause : le pod utilise `dnsPolicy: None` avec un `dnsConfig.nameservers` injoignable (`192.0.2.53`) → aucune résolution. Les champs DNS d'un pod sont **immutables** → **supprimer & recréer** avec la politique par défaut (`ClusterFirst`, qui utilise CoreDNS).
```bash
kubectl -n trouble delete pod dns-check
kubectl -n trouble run dns-check --image=busybox:1.36 --labels=app=dns-check \
  -- sh -c "sleep 100000"
# dnsPolicy ClusterFirst par défaut → résout via CoreDNS (10.96.0.10)
kubectl -n trouble exec dns-check -- nslookup kubernetes.default.svc.cluster.local
```
> ⚠️ `busybox nslookup` n'applique pas les *search domains* du `resolv.conf` : le nom court `kubernetes.default` renvoie `NXDOMAIN` même quand le DNS marche. Teste avec le **FQDN** `kubernetes.default.svc.cluster.local` (c'est ce que vérifie `grade.sh`).

### T15 — Pod `Pending` (`trouble/stuck`)
Cause : `nodeSelector disktype=nvme` qu'aucun node ne satisfait. Le `nodeSelector` d'un pod est **immutable** → **supprimer & recréer**.
```bash
kubectl -n trouble delete pod stuck
kubectl -n trouble run stuck --image=nginx:1.29-alpine
```

### T16 — Secret d'env manquant (`trouble/billing`)
```bash
kubectl -n trouble create secret generic billing-secret --from-literal=API_KEY=abc123
kubectl -n trouble rollout status deploy/billing     # pods démarrent
```

---

## 🔁 Recommencer à zéro
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/setup.sh"   # ré-initialise l'environnement
```
> `setup.sh` nettoie les namespaces d'exam, le PV, le ClusterRole/Binding, retire le taint de `w1`, les labels `disktype` et dé-cordonne les workers. **⚠️ Il ne peut PAS annuler l'upgrade de la T2** : si `cp1` est déjà en 1.35, redéploie le cluster (`vagrant destroy -f && vagrant up --no-parallel`). Le **static pod T3** sur `w1` se retire à la main :
> ```bash
> vagrant ssh w1 -c "sudo rm -f /etc/kubernetes/manifests/static-web.yaml"
> ```
