# 🔧 Lab — Troubleshooting transverse · SOLUTIONS

> Diagnostic + réparation de chaque panne. Le grader teste **le résultat** (objet réparé,
> pod `Running`, trafic qui passe), pas la méthode : plusieurs chemins sont souvent valides.
> Réflexe commun : **`kubectl describe` → section Events**, puis `logs` / `logs -p`.

---

## 🏛️ ARCH — Cluster Architecture & Nodes

### A1 — RBAC : `deploy-bot` n'a aucun droit
**Diagnostic**
```bash
kubectl -n ts-arch auth can-i list pods --as=system:serviceaccount:ts-arch:deploy-bot   # no
kubectl -n ts-arch get rolebinding deploy-bot-read -o yaml   # subjects.name = deploy-bot-typo (≠ SA réel)
```
**Réparation** — corriger le sujet de la RoleBinding :
```bash
kubectl -n ts-arch patch rolebinding deploy-bot-read --type=json \
  -p='[{"op":"replace","path":"/subjects/0/name","value":"deploy-bot"}]'
# (ou: kubectl -n ts-arch edit rolebinding deploy-bot-read  →  name: deploy-bot)
```
**Vérif** : `... can-i list pods ... = yes` et `... can-i delete pods ... = no`.
**Points clés** : un `RoleBinding` lie un **sujet** (SA/user/group) à un `Role`. Une typo dans
`subjects[].name` casse silencieusement les droits (aucune erreur). `auth can-i --as=` est l'outil de diagnostic.

### A2 — Static pod cassé sur `cp1`
**Diagnostic**
```bash
kubectl get pod ts-static-cp1 -n default          # ImagePullBackOff
kubectl describe pod ts-static-cp1 | tail          # Failed to pull image "nginx:1.29-nope"
```
**Réparation** — sur le noeud `cp1`, éditer le manifest statique :
```bash
vagrant ssh cp1            # depuis l'hôte
sudo sed -i 's/nginx:1.29-nope/nginx:1.29-alpine/' /etc/kubernetes/manifests/ts-static.yaml
# le kubelet détecte le changement et recrée le pod tout seul
```
**Points clés** : un **static pod** est géré par le **kubelet** (répertoire `/etc/kubernetes/manifests/`),
pas par l'API. On ne le corrige pas avec `kubectl edit` (le mirror pod est en lecture seule) mais **sur le noeud**.
Il n'est pas soumis au scheduler → le taint control-plane de `cp1` ne le gêne pas. `ownerReferences.kind=Node` confirme un mirror pod.

### A3 — Noeud `w1` « hors service » (2 causes)
**Diagnostic**
```bash
kubectl -n ts-nodes get deploy billing            # 0/1 disponible
kubectl -n ts-nodes describe pod -l app=billing | tail   # FailedScheduling: unschedulable + untolerated taint
kubectl describe node w1 | grep -E 'Taints|Unschedulable'
```
**Réparation** — lever les **deux** blocages :
```bash
kubectl uncordon w1                          # 1) SchedulingDisabled
kubectl taint node w1 maintenance-           # 2) taint NoSchedule
# variante pour (2) : garder le taint et ajouter une toleration au Deployment
#   kubectl -n ts-nodes patch deploy billing --type=json -p='[{"op":"add","path":"/spec/template/spec/tolerations","value":[{"key":"maintenance","operator":"Exists","effect":"NoSchedule"}]}]'
```
**Points clés** : deux mécanismes **cumulatifs** empêchent le placement — `cordon`
(`.spec.unschedulable`) et un **taint** `NoSchedule`. `describe node` révèle les deux. Rappels effets de taint :
`NoSchedule` (bloque le placement), `PreferNoSchedule` (évite si possible), `NoExecute` (**évince** en plus les pods sans toleration).

### A4 — ConfigMap coincée en `Terminating`
**Diagnostic**
```bash
kubectl -n ts-arch get cm stuck-cm            # AGE ancien, jamais supprimée
kubectl -n ts-arch get cm stuck-cm -o jsonpath='{.metadata.finalizers}{"\n"}'   # ["example.com/hold"]
```
**Réparation** — retirer le finalizer :
```bash
kubectl -n ts-arch patch cm stuck-cm --type=merge -p '{"metadata":{"finalizers":null}}'
```
**Points clés** : un objet avec `deletionTimestamp` **+** un `finalizer` reste `Terminating` tant que le
finalizer n'est pas retiré (le controller censé le faire est absent). Vider `metadata.finalizers` débloque la suppression.

---

## 📦 WORK — Workloads & Scheduling

### W1 — `web` en `ImagePullBackOff`
```bash
kubectl -n ts-work describe deploy web | tail          # tag "nginx:1.29-nope" introuvable
kubectl -n ts-work set image deploy/web web=nginx:1.29-alpine
```
**Points clés** : sur un **Deployment**, `set image` (ou `edit`) déclenche un rollout — pas besoin de recréer.

### W2 — `crasher` en `CrashLoopBackOff`
```bash
kubectl -n ts-work logs crasher --previous       # -p : logs de l'instance qui a planté
# la commande sort en erreur (exit 1). command/args sont IMMUABLES sur un pod → recréer :
kubectl -n ts-work delete pod crasher
kubectl -n ts-work run crasher --image=busybox:1.36 --command -- sh -c 'sleep 100000'
```
**Points clés** : `logs --previous` est indispensable en CrashLoop (le conteneur courant vient de redémarrer).
Un `command:` erroné écrase l'`ENTRYPOINT` et fait sortir le conteneur aussitôt.

### W3 — `checkout` en `CreateContainerConfigError`
```bash
kubectl -n ts-work describe pod checkout | tail   # secret "app-secret" : clé "password" introuvable
kubectl -n ts-work patch secret app-secret --type=merge \
  -p "{\"data\":{\"password\":\"$(printf 'S3cret' | base64 -w0)\"}}"
# le kubelet réessaie seul → checkout passe Running
```
**Points clés** : une **clé** absente dans un `secretKeyRef`/`configMapKeyRef` bloque la création du conteneur.
Ajouter la clé suffit (le pod n'a pas besoin d'être recréé, le kubelet retente).

### W4 — `report` en `Pending` (ressources)
```bash
kubectl -n ts-work describe pod report | tail     # 0/3 nodes: Insufficient memory/cpu
kubectl -n ts-work delete pod report
kubectl -n ts-work run report --image=nginx:1.29-alpine
```
**Points clés** : `requests` déraisonnables → aucun noeud n'a l'`Allocatable` suffisant. Les `resources`
sont immuables sur un pod → recréer avec des demandes réalistes (ou aucune).

### W5 — `analytics` en `Pending` (nodeSelector)
```bash
kubectl -n ts-work describe pod analytics | tail  # didn't match node selector disktype=ssd
kubectl label node w2 disktype=ssd                # rendre un noeud éligible
# (ou recréer le pod sans le nodeSelector)
```
**Points clés** : un `nodeSelector` sans noeud correspondant laisse le pod `Pending`. Deux réparations :
**labelliser** un noeud, ou retirer/corriger le sélecteur.

### W6 — `frontend` jamais `Ready`
```bash
kubectl -n ts-work get pods -l app=frontend       # Running mais 0/1 READY
kubectl -n ts-work describe pod -l app=frontend | grep -A3 Readiness   # probe :8080 en échec
kubectl -n ts-work patch deploy frontend --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]'
```
**Points clés** : une **readinessProbe** qui échoue laisse le pod `Running` mais **NotReady** → il est retiré
des endpoints de son Service. Le symptôme (« pas de trafic ») est réseau, la **cause** est la sonde.

---

## 🌐 NET — Services & Networking

### N1 — `api-svc` sans endpoints
```bash
kubectl -n ts-net get endpoints api-svc           # <none>
kubectl -n ts-net get pods --show-labels          # app=api  (le svc cible app=api-v1)
kubectl -n ts-net patch svc api-svc --type=merge -p '{"spec":{"selector":{"app":"api"}}}'
```
**Points clés** : `endpoints` vide = **selector mismatch** (ou pods NotReady). Comparer le `selector`
du Service aux **labels** réels des pods.

### N2 — `shop-svc` : mauvais `targetPort`
```bash
kubectl -n ts-net get svc shop-svc -o wide        # port 80 → targetPort 8080
kubectl -n ts-net exec shop-client -- wget -T4 -qO- http://shop-svc   # échoue
kubectl -n ts-net patch svc shop-svc --type=json \
  -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'
```
**Points clés** : endpoints présents **mais** trafic KO ⇒ souvent `targetPort` ≠ port réel du conteneur.
`port` = port du Service, `targetPort` = port du conteneur cible.

### N3 — NetworkPolicy `default-deny` bloque `client → backend`
```bash
kubectl -n ts-netpol get netpol                   # default-deny-ingress (podSelector: {})
kubectl -n ts-netpol exec client -- wget -T4 -qO- http://backend   # bloqué
kubectl -n ts-netpol apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client-to-backend, namespace: ts-netpol }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - podSelector: { matchLabels: { app: client } }
    ports:
    - { protocol: TCP, port: 80 }
EOF
# (variante : supprimer la policy default-deny si aucune restriction n'est requise)
```
**Points clés** : les NetworkPolicy sont **additives** (OR). Un `default-deny` (podSelector `{}`, Ingress)
bloque tout ; il faut une policy qui **autorise** explicitement le flux voulu. Calico applique l'enforcement.

### N4 — `dns-broken` ne résout pas les services
```bash
kubectl -n ts-net exec dns-broken -- nslookup kubernetes.default   # échoue
kubectl -n ts-net get pod dns-broken -o jsonpath='{.spec.dnsPolicy}{"\n"}'   # Default
# dnsPolicy est immuable sur un pod → recréer avec ClusterFirst :
kubectl -n ts-net delete pod dns-broken
kubectl -n ts-net run dns-broken --image=busybox:1.36 \
  --overrides='{"spec":{"dnsPolicy":"ClusterFirst"}}' --command -- sh -c 'sleep 100000'
```
**Points clés** : `dnsPolicy: Default` fait hériter le `resolv.conf` **du noeud** → **pas** de résolution
`*.svc.cluster.local`. `ClusterFirst` (le vrai défaut) utilise **CoreDNS**.

---

## 💾 STO — Storage

### S1 — PVC `data` en `Pending`
```bash
kubectl -n ts-storage get pvc data                # Pending
kubectl -n ts-storage describe pvc data | tail    # no volume plugin / no PV for storageClassName "fast"
kubectl get pv                                     # pv-small existe en storageClassName "slow"
# storageClassName est immuable sur une PVC → recréer alignée sur le PV :
kubectl -n ts-storage delete pvc data
kubectl -n ts-storage apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: ts-storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: slow
  resources: { requests: { storage: 3Gi } }
EOF
```
**Points clés** : sans provisioner dynamique, une PVC ne se lie qu'à un **PV existant** dont la
`storageClassName`, l'`accessMode` et la capacité (≥ demande) correspondent.

### S2 — `app` bloqué : PVC manquante
```bash
kubectl -n ts-storage describe pod app | tail     # persistentvolumeclaim "app-pvc" not found
kubectl -n ts-storage apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: app-pvc, namespace: ts-storage }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local
  resources: { requests: { storage: 5Gi } }
EOF
# la PVC se lie à pv-app → le pod démarre (le kubelet retente le montage)
```
**Points clés** : un volume `persistentVolumeClaim` pointant vers une PVC **inexistante** bloque le pod en
`ContainerCreating`. Créer la PVC (compatible avec un PV libre) débloque le montage sans recréer le pod.

---

## 🧭 Méthode générale (rappel)

1. **Vue d'ensemble** : `kubectl get pods -A --field-selector=status.phase!=Running` + `get events -A --sort-by=.lastTimestamp`.
2. **Un objet** : `describe` (Events !) → `logs` / `logs -p` → `get -o yaml`.
3. **Scheduling** (`Pending`) : `describe pod` → cause `FailedScheduling` (ressources, taint, nodeSelector, cordon).
4. **Réseau** (« pas de trafic ») : `get endpoints` → selector/probes ; `targetPort` ; NetworkPolicy ; DNS (`dnsPolicy`).
5. **Noeud** : `describe node` (Taints, Unschedulable, Conditions, Allocatable).
