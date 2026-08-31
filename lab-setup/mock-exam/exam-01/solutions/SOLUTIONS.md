# ✅ CKA — Mock exam · SOLUTIONS

> **Open this file only after your attempt.** Each solution matches exactly the criteria in `grade.sh`.
> All commands run from `cp1` (`vagrant ssh cp1`), except T3 (on `w1`).

---

## 🏛️ Cluster Architecture

### T1 — RBAC (`rbac-test`)
```bash
kubectl -n rbac-test create sa deploy-bot
kubectl -n rbac-test create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n rbac-test create rolebinding deploy-bot-read \
  --role=pod-reader --serviceaccount=rbac-test:deploy-bot

# Check
kubectl auth can-i list   pods --as=system:serviceaccount:rbac-test:deploy-bot -n rbac-test   # yes
kubectl auth can-i delete pods --as=system:serviceaccount:rbac-test:deploy-bot -n rbac-test   # no
```

### T2 — etcd snapshot (`/opt/etcd-backup.db` on cp1)
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup.db

# Check
sudo ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db -w table
```
> If `etcdctl` is not installed: `sudo apt-get install -y etcd-client` (done by `setup.sh`), or go through the pod: `kubectl -n kube-system exec etcd-cp1 -- etcdctl ... snapshot save /var/lib/etcd/... ` then copy.

### T3 — Static Pod on `w1`
```bash
vagrant ssh w1          # from the host (or direct ssh)
sudo tee /etc/kubernetes/manifests/static-web.yaml >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: static-web
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    ports: [{ containerPort: 80 }]
EOF
# The kubelet detects it on its own → the mirror pod "static-web-w1" appears on the API side.
```

### T4 — Maintenance `w2`
```bash
kubectl cordon w2
kubectl get node w2      # STATUS: Ready,SchedulingDisabled
```

---

## 📦 Workloads & Scheduling

### T5 — Deployment `web` (`workloads`)
```bash
kubectl -n workloads create deployment web --image=nginx:1.29-alpine --replicas=3
```

### T6 — ConfigMap → env (`workloads`)
```bash
kubectl -n workloads create configmap app-config --from-literal=APP_COLOR=blue

kubectl -n workloads apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: color-pod, namespace: workloads }
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: ["sh","-c","sleep 100000"]
    env:
    - name: APP_COLOR
      valueFrom:
        configMapKeyRef: { name: app-config, key: APP_COLOR }
EOF
```

### T7 — nodeSelector (`workloads`)
```bash
kubectl label node w1 disktype=ssd

kubectl -n workloads apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: ssd-pod, namespace: workloads }
spec:
  nodeSelector: { disktype: ssd }
  containers:
  - { name: web, image: nginx:1.29-alpine }
EOF
```

---

## 🌐 Services & Networking

### T8 — ClusterIP `web-svc` (`workloads`)
```bash
kubectl -n workloads expose deployment web --name=web-svc --port=80 --target-port=80
kubectl -n workloads get endpoints web-svc      # 3 IPs
```

### T9 — NodePort `web-np` (`workloads`)
```bash
kubectl -n workloads expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
kubectl -n workloads patch svc web-np -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30080}]}}'
# (or edit the YAML to set nodePort: 30080)
```

### T10 — NetworkPolicy (`netpol`)
```bash
kubectl -n netpol apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: backend-allow-frontend, namespace: netpol }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: { matchLabels: { app: frontend } }
    ports: [{ port: 80, protocol: TCP }]
EOF

# Check
kubectl -n netpol exec frontend -- wget -T3 -qO- http://backend >/dev/null && echo "frontend OK"
kubectl -n netpol exec client   -- wget -T3 -qO- http://backend    # should time out
```

---

## 💾 Storage

### T11 — PV + PVC (`storage`)
```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-manual }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  hostPath: { path: /mnt/data }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-manual, namespace: storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources: { requests: { storage: 500Mi } }
EOF

kubectl -n storage get pvc pvc-manual   # Bound → pv-manual
```

### T12 — Pod mounting the PVC (`storage`)
```bash
kubectl -n storage apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: pv-pod, namespace: storage }
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    volumeMounts: [{ name: data, mountPath: /usr/share/nginx/html }]
  volumes:
  - name: data
    persistentVolumeClaim: { claimName: pvc-manual }
EOF
```

---

## 🔧 Troubleshooting

### T13 — Broken image (`trouble/tshoot-web`)
```bash
kubectl -n trouble set image deploy/tshoot-web web=nginx:1.29-alpine
kubectl -n trouble rollout status deploy/tshoot-web
```

### T14 — Service with no endpoints (`trouble/api-svc`)
Cause: the Service selector (`app=apiv1`) matches no pod (`app=api`).
```bash
kubectl -n trouble patch svc api-svc -p '{"spec":{"selector":{"app":"api"}}}'
kubectl -n trouble get endpoints api-svc     # IPs present
```

### T15 — Pod `Pending` (`trouble/hungry`)
Cause: `requests.memory: 100Gi` (+ `cpu: 50`) → no node can accommodate it. A pod's `resources` are **immutable** → **delete & recreate**.
```bash
kubectl -n trouble delete pod hungry
kubectl -n trouble apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: hungry, namespace: trouble }
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    resources: { requests: { memory: 64Mi, cpu: 100m } }
EOF
```

### T16 — Missing ConfigMap (`trouble/cfg-app`)
```bash
kubectl -n trouble create configmap cfg-app-config --from-literal=app.properties=mode=prod
kubectl -n trouble rollout status deploy/cfg-app     # pods start
```

---

## 🔁 Start over
```bash
vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/setup.sh"   # reset the environment
```
> Note: `setup.sh` cleans up the exam namespaces, the PV, the w1 label, uncordons w2 and deletes the snapshot. The **T3 static pod** on `w1` must be removed by hand: `vagrant ssh w1 -c "sudo rm -f /etc/kubernetes/manifests/static-web.yaml"`.
