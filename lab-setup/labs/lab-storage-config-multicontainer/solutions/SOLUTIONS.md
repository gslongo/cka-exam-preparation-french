# ✅ Lab — Stockage · ConfigMap/Secrets · Sidecars · SOLUTIONS

> **N'ouvre ce fichier qu'après ta tentative.** Chaque solution correspond exactement aux critères de `grade.sh`.
> Toutes les commandes sont à lancer depuis `cp1` (`vagrant ssh cp1`).

---

## 💾 Domaine A — Stockage persistant

### A1 — StorageClass `fast-local`
```bash
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
provisioner: example.com/fast-provisioner
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

kubectl get sc fast-local -o wide
```
> Points clés : une *StorageClass* n'a **pas** de `spec` — `provisioner`, `reclaimPolicy`,
> `volumeBindingMode` et `allowVolumeExpansion` sont au **premier niveau**. `WaitForFirstConsumer`
> retarde le provisioning jusqu'au scheduling du Pod (indispensable en multi-AZ). Le provisioner ici
> est illustratif : aucun volume ne sera réellement créé (on note l'objet).

### A2 — Lier un PVC à un PV statique
```bash
kubectl -n storage-lab apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: 2Gi
EOF

kubectl -n storage-lab get pvc app-data          # STATUS=Bound, VOLUME=pv-data
```
> Points clés : binding **statique** = pas de provisioner. Le contrôleur choisit un PV compatible :
> même `storageClassName` (`manual`), `accessModes` inclus (RWO), capacité **≥** demande (2Gi ≤ 5Gi).
> On peut donc obtenir un PV **plus grand** que demandé.

### A3 — Consommer le PVC dans un Pod
```bash
kubectl -n storage-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "100000"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-data
EOF

kubectl -n storage-lab wait --for=condition=Ready pod/app --timeout=60s
kubectl -n storage-lab exec app -- touch /data/ready        # crée le fichier attendu
kubectl -n storage-lab exec app -- ls -l /data
```
> Points clés : le Pod référence le PVC par `claimName` (il ne **possède** pas le PVC → le PVC survit au Pod).
> Le fichier écrit dans `/data` vit sur le `hostPath` du node où atterrit le Pod (peu importe ici : on relit via `exec`).

### A4 — Récupérer un PV bloqué en `Released`
```bash
# 1) Diagnostic : le claimRef périmé bloque le rebinding
kubectl get pv pv-archive                                   # STATUS=Released
kubectl get pv pv-archive -o jsonpath='{.spec.claimRef}{"\n"}'

# 2) Retirer le claimRef → le PV repasse Available
kubectl patch pv pv-archive --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
#   (équivalent interactif : kubectl edit pv pv-archive  → supprimer tout le bloc spec.claimRef)
kubectl get pv pv-archive                                   # STATUS=Available

# 3) Nouveau PVC qui se lie au PV libéré
kubectl -n storage-lab apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: archive
  resources:
    requests:
      storage: 2Gi
EOF

kubectl -n storage-lab get pvc archive                      # STATUS=Bound, VOLUME=pv-archive
```
> Points clés : en `reclaimPolicy: Retain`, supprimer le PVC laisse le PV en **`Released`** avec un
> `spec.claimRef` (namespace + name + **uid** obsolète) qui l'empêche de se rebinder — même à un PVC de
> même nom (l'`uid` ne correspond plus). Retirer `claimRef` → `Available`, puis un PVC compatible s'y lie.
> ⚠️ Les **données** restent sur le volume ; pour repartir propre, on nettoierait le backend d'abord.

---

## ⚙️ Domaine B — ConfigMap & Secrets

### B1 — ConfigMap multi-clés
```bash
kubectl -n config-lab create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=info \
  --from-literal=MAX_CONNECTIONS=100

kubectl -n config-lab get cm app-config -o yaml
```
> Points clés : `--from-literal` par clé. (Autres sources utiles : `--from-file=cfg.properties`,
> `--from-env-file=vars.env`.) Toutes ces clés sont des identifiants valides → réutilisables tels quels en `envFrom` (B3).

### B2 — Secret Opaque
```bash
kubectl -n config-lab create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=S3cr3t-pass

kubectl -n config-lab get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
```
> Points clés : `secret generic` = type **`Opaque`**. Les valeurs sont **base64** (encodage, **pas**
> chiffrement) → toute personne pouvant lire le Secret voit la valeur. `create secret generic` encode
> automatiquement ; en YAML brut on mettrait le base64 sous `data:` (ou le clair sous `stringData:`).

### B3 — Injecter la config en variables d'environnement
```bash
kubectl -n config-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: ["sleep", "100000"]
    envFrom:
    - configMapRef:
        name: app-config
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
EOF

kubectl -n config-lab exec api -- printenv APP_MODE MAX_CONNECTIONS DB_PASSWORD
```
> Points clés : `envFrom` importe **toutes** les clés de la ConfigMap comme variables homonymes
> (`APP_MODE`, `LOG_LEVEL`, `MAX_CONNECTIONS`). `secretKeyRef` cible **une** clé précise du Secret et la
> renomme (`DB_PASSWORD`). ⚠️ Injecté en **variable d'env**, une valeur de ConfigMap/Secret est **figée**
> à la création du Pod → un changement ultérieur nécessite `kubectl rollout restart` (ou recréer le Pod).

### B4 — Monter une ConfigMap en volume
```bash
# 1) ConfigMap avec un contenu de fichier (clé index.html)
kubectl -n config-lab create configmap web-index \
  --from-literal=index.html='<h1>CKA Storage Lab</h1>'

# 2) Pod nginx qui monte la ConfigMap sur le docroot
kubectl -n config-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
  - name: web
    image: nginx:1.29-alpine
    volumeMounts:
    - name: content
      mountPath: /usr/share/nginx/html
  volumes:
  - name: content
    configMap:
      name: web-index
EOF

kubectl -n config-lab exec web -- cat /usr/share/nginx/html/index.html
```
> Points clés : une ConfigMap montée en **volume** expose **chaque clé → un fichier** (`mountPath/<clé>`,
> contenu = valeur). La clé `index.html` devient donc `/usr/share/nginx/html/index.html`. Options utiles :
> `items:` (ne monter que certaines clés, éventuellement renommées via `path`), `defaultMode` (permissions),
> `subPath` (monter **un** fichier sans masquer le dossier — mais casse la mise à jour à chaud).
> Contrairement à `envFrom`, un volume ConfigMap est **rafraîchi** automatiquement (délai kubelet, sauf `subPath`).

---

## 🧩 Domaine C — Sidecars & Pods multi-conteneurs

### C1 — Deux conteneurs partageant un `emptyDir`
```bash
kubectl -n multi-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: shared-logs
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /var/log/app/app.log; sleep 1; done"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: sidecar
    image: busybox:1.36
    command: ["sh", "-c", "tail -f /var/log/app/app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  volumes:
  - name: logs
    emptyDir: {}
EOF

kubectl -n multi-lab exec shared-logs -c sidecar -- head /var/log/app/app.log
```
> Points clés : un `emptyDir` est un volume **éphémère partagé** par tous les conteneurs du Pod (créé au
> démarrage du Pod, effacé à sa suppression). Le **même** volume monté aux deux conteneurs = canal d'échange
> writer→reader (patron classique du log shipper). `emptyDir.medium: Memory` = tmpfs (compté dans `limits.memory`).

### C2 — Sidecar « natif » (initContainer `restartPolicy: Always`)
```bash
kubectl -n multi-lab apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web-agent
spec:
  initContainers:
  - name: log-agent            # ← sidecar NATIF : initContainer + restartPolicy Always
    image: busybox:1.36
    restartPolicy: Always
    command: ["sleep", "100000"]
  containers:
  - name: web
    image: nginx:1.29-alpine
EOF

kubectl -n multi-lab get pod web-agent -o jsonpath='{.status.initContainerStatuses[0].state}{"\n"}'
```
> Points clés : depuis K8s **1.29**, un `initContainer` avec **`restartPolicy: Always`** est un **sidecar
> natif** : il démarre **avant** les conteneurs principaux (comme un init) **mais** reste vivant tout le
> long (contrairement à un initContainer classique qui doit se terminer). Avantages vs le patron « 2ᵉ
> conteneur » : ordre de démarrage garanti, ne bloque pas la fin d'un Job, cycle de vie géré par le kubelet.

---

> 💡 Rappel : aucun provisioner CSI n'est installé — la *StorageClass* (A1) est notée sur l'**objet**,
> tandis que le binding statique (A2/A4) et les Pods (A3, B3, B4, C1, C2) sont validés **en direct**.
> En production, un provisioner (local-path, EBS CSI, Ceph…) matérialiserait le stockage dynamique.
