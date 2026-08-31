# ✅ CKA — Mock exam #2 (advanced) · SOLUTIONS

> **Open this file only after your attempt.** Each solution matches exactly the criteria of `grade.sh`.
> All commands run from `cp1` (`vagrant ssh cp1`), **except T3** (on `w1`).

---

## 🏛️ Cluster Architecture

### T1 — Cluster-scoped RBAC (`platform`)
```bash
kubectl -n platform create sa ci-bot

# ClusterRole limited to deployments (no nodes → deliberately bounded rights)
kubectl create clusterrole deploy-admin \
  --verb=get,list,watch,create,update,patch \
  --resource=deployments.apps

kubectl create clusterrolebinding ci-bot-deploy \
  --clusterrole=deploy-admin \
  --serviceaccount=platform:ci-bot

# Verify
kubectl auth can-i create deployments --as=system:serviceaccount:platform:ci-bot -n default   # yes
kubectl auth can-i delete nodes       --as=system:serviceaccount:platform:ci-bot               # no
```

### T2 — Control plane upgrade 1.34 → 1.35 (on `cp1`) · ⚠️ do this LAST
> **Irreversible**: once `cp1` is on 1.35, `setup.sh` cannot roll back → redeploy needed to retake the exam.
```bash
# 1) Switch the apt repo from v1.34 → v1.35 (key + list)
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo sed -i 's#v1\.34/deb#v1.35/deb#' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

# 2) Install kubeadm 1.35 (the package is "hold" → unhold first)
sudo apt-cache madison kubeadm | head           # find the available patch, e.g. 1.35.0-1.1
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm='1.35.0-1.1'     # adjust to the listed patch
sudo apt-mark hold kubeadm
kubeadm version

# 3) Plan then apply the control plane upgrade
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.35.0 -y            # adjust to the exact patch

# 4) Drain cp1, upgrade kubelet + kubectl, restart, uncordon
kubectl drain cp1 --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet='1.35.0-1.1' kubectl='1.35.0-1.1'
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon cp1

# 5) Verify
kubectl get node cp1        # STATUS Ready, VERSION v1.35.x
```
> ⚠️ **Do NOT upgrade the workers.** `grade.sh` only grades `cp1`. Draining `w1`/`w2` **permanently evicts** the "naked" pods from the other tasks (T4 `pinned`, T6 `secret-pod`, T7 `tolerant`, T12 `app`, T14 `dns-check`, T15 `stuck`, `secure` seeds): with no controller they are **not recreated** → you lose those points. Draining `cp1` is safe (it hosts no exam pod).

### T3 — Static Pod with label `role=cache` (on `w1`)
```bash
vagrant ssh w1          # from the host
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
# The kubelet detects it on its own → the mirror pod "static-web-w1" appears on the API side.
```
> The static pod is not subject to the scheduler: the `w1` taint (T7) does not bother it.

### T4 — Manual scheduling on `w2` (`apps`)
```bash
kubectl -n apps apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: pinned, namespace: apps }
spec:
  nodeName: w2        # bypass the scheduler
  containers:
  - { name: web, image: nginx:1.29-alpine }
EOF
```

---

## 📦 Workloads & Scheduling

### T5 — Deployment `api` + rollout strategy (`apps`)
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
> The 3 replicas land on `w2` (cp1 and `w1` are tainted).

### T6 — Secret → env variable (`apps`)
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
  nodeSelector: { kubernetes.io/hostname: w1 }   # target w1
  tolerations:
  - key: dedicated
    operator: Equal
    value: cka
    effect: NoSchedule
  containers:
  - { name: web, image: nginx:1.29-alpine }
EOF
```
> Without the toleration, the pod would stay `Pending` (w1 repels everything else).

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
> The lab has **no** Ingress controller → the Ingress will not get an address and will not actually route; `grade.sh` only checks the **definition** (host / path / backend `api-np:80`).

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

# Verify
kubectl -n secure exec web     -- wget -T3 -qO- http://db >/dev/null && echo "web OK"
kubectl -n secure exec scanner -- wget -T3 -qO- http://db    # should time out
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

### T12 — Pod mounted via `subPath` (`storage`)
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
> Pitfall: with `subPath` on a `hostPath`, the base directory must exist on the node, otherwise the mount fails (`stat /mnt/data-02: no such file or directory` → pod in `CreateContainerConfigError`). Hence the `type: DirectoryOrCreate` on the PV in T11, which lets the kubelet create the folder.

---

## 🔧 Troubleshooting

### T13 — readinessProbe on the wrong port (`trouble/frontend`)
Cause: the probe queries `:8080` while nginx listens on `:80`.
```bash
kubectl -n trouble patch deploy frontend --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]'
kubectl -n trouble rollout status deploy/frontend
```

### T14 — Broken DNS resolution (`trouble/dns-check`)
Cause: the pod uses `dnsPolicy: None` with an unreachable `dnsConfig.nameservers` (`192.0.2.53`) → no resolution. A pod's DNS fields are **immutable** → **delete & recreate** with the default policy (`ClusterFirst`, which uses CoreDNS).
```bash
kubectl -n trouble delete pod dns-check
kubectl -n trouble run dns-check --image=busybox:1.36 --labels=app=dns-check \
  -- sh -c "sleep 100000"
# dnsPolicy ClusterFirst by default → resolves via CoreDNS (10.96.0.10)
kubectl -n trouble exec dns-check -- nslookup kubernetes.default.svc.cluster.local
```
> ⚠️ `busybox nslookup` does not apply the *search domains* from `resolv.conf`: the short name `kubernetes.default` returns `NXDOMAIN` even when DNS works. Test with the **FQDN** `kubernetes.default.svc.cluster.local` (that's what `grade.sh` checks).

### T15 — Pod `Pending` (`trouble/stuck`)
Cause: `nodeSelector disktype=nvme` that no node satisfies. A pod's `nodeSelector` is **immutable** → **delete & recreate**.
```bash
kubectl -n trouble delete pod stuck
kubectl -n trouble run stuck --image=nginx:1.29-alpine
```

### T16 — Missing env Secret (`trouble/billing`)
```bash
kubectl -n trouble create secret generic billing-secret --from-literal=API_KEY=abc123
kubectl -n trouble rollout status deploy/billing     # pods start
```

---

## 🔁 Start over
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/setup.sh"   # re-initialise the environment
```
> `setup.sh` cleans up the exam namespaces, the PV, the ClusterRole/Binding, removes the `w1` taint, the `disktype` labels and uncordons the workers. **⚠️ It CANNOT undo the T2 upgrade**: if `cp1` is already on 1.35, redeploy the cluster (`vagrant destroy -f && vagrant up --no-parallel`). The **T3 static pod** on `w1` is removed by hand:
> ```bash
> vagrant ssh w1 -c "sudo rm -f /etc/kubernetes/manifests/static-web.yaml"
> ```
