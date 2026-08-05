# kubectl — trucs & astuces (jour J)

> Concentré de commandes utiles pour économiser du temps à l'exam. **N'apprendre par cœur que la section ⚡**.

## ⚡ À taper dans les 30 premières secondes

```bash
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

## 🗂️ Contexte & namespace

```bash
kubectl config get-contexts
kubectl config use-context <ctx>
kubectl config set-context --current --namespace=<ns>
kubectl config view --minify                    # contexte courant seulement

# --- Créer un cert client user (méthode openssl directe, alt. à la CSR API) ---
openssl genrsa -out dan.key 2048
openssl req -new -key dan.key -out dan.csr -subj "/CN=DevDan/O=development"  # CN=user, O=group
sudo openssl x509 -req -in dan.csr \
  -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial -out dan.crt -days 45

# --- Construire un kubeconfig utilisateur (après un client cert signé, cf. Q18/CSR) ---
# ordre : cluster → user → context → use-context
kubectl config set-cluster kubernetes \
  --server=https://<apiserver>:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true
kubectl config set-credentials bob \
  --client-certificate=bob.crt --client-key=bob.key --embed-certs=true
kubectl config set-context bob@kubernetes --cluster=kubernetes --user=bob --namespace=dev
kubectl config use-context bob@kubernetes
# --embed-certs=true : inline les certs (portable) au lieu de stocker les chemins
# --kubeconfig=bob.config sur chaque cmd : écrire un fichier dédié (pas ~/.kube/config)
```

## 🚀 Génération rapide de manifests (`$do`)

```bash
# Pod
k run p --image=nginx $do
k run p --image=nginx --labels="app=web,env=prod" $do
k run p --image=busybox --restart=Never --command -- sleep 3600 $do

# Deployment
k create deploy web --image=nginx --replicas=3 $do
k create deploy web --image=nginx --port=80 $do

# Service
k expose deploy web --port=80 --target-port=8080 $do
k create service clusterip web --tcp=80:8080 $do
k create service nodeport web --tcp=80:8080 --node-port=30080 $do

# Ingress
k create ingress web --rule="app.ex.com/*=web:80,tls=web-tls" --class=nginx $do

# ConfigMap / Secret
k create cm app --from-literal=key=value --from-file=./config.txt $do
k create secret generic db --from-literal=password=s3cr3t $do
k create secret docker-registry regcred \
  --docker-server=... --docker-username=... --docker-password=... $do
# Variantes --from-* (piège exam) :
#   --from-literal=k=v        → 1 clé k
#   --from-file=config.js     → clé = NOM du fichier, valeur = contenu
#   --from-file=app=config.js → clé custom "app"
#   --from-file=dir/          → 1 clé par fichier du dossier
#   --from-env-file=f.env     → 1 clé par ligne KEY=val  (≠ --from-file !)

# RBAC
k create role dev --verb=get,list,watch --resource=pods $do
k create rolebinding devbind --role=dev --serviceaccount=team:bot $do
k create clusterrole nro --verb=list --resource=nodes $do
k create clusterrolebinding nrobind --clusterrole=nro --user=alice $do

# Jobs
k create job one --image=busybox -- echo hi $do
k create cronjob backup --schedule="0 3 * * *" --image=busybox -- /b.sh $do

# Namespace / SA
k create ns team-a $do
k create sa deploy-bot $do

# Poddisruptionbudget
k create pdb web --selector=app=web --min-available=2 $do
```

## 🔎 `kubectl explain`

Toujours plus rapide que la doc quand tu doutes d'un champ :

```bash
k explain pod.spec.containers                          # champs d'un container
k explain deploy.spec.strategy.rollingUpdate           # niveau précis
k explain deploy --recursive | less                    # tout l'arbre
k explain deploy --recursive | grep -A1 resources
```

## 🎯 Sélecteurs & filtres

```bash
# labels
k get pod -l app=web
k get pod -l 'env in (prod,stage)'
k get pod -l 'app,env!=dev'
k get pod --show-labels

# fields
k get pod --field-selector status.phase=Running
k get pod --field-selector spec.nodeName=<node>
k get pod -A --field-selector status.phase!=Running

# tri
k get pod -A --sort-by=.metadata.creationTimestamp
k get pod -A --sort-by=.status.startTime
k top pod -A --sort-by=memory
```

## 📤 Sorties personnalisées

```bash
# JSONPath
k get pod -o jsonpath='{.items[*].metadata.name}'
k get pod <p> -o jsonpath='{.status.podIP}{"\n"}'
k get pod <p> -o jsonpath='{range .spec.containers[*]}{.name}={.image}{"\n"}{end}'

# custom-columns
k get pod -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'

# JSON complet vers jq
k get pod <p> -o json | jq '.spec.containers[].resources'
```

## 🩹 Édition & patch

```bash
k edit deploy web                                      # ouvre $KUBE_EDITOR (vi)
k set image deploy/web c=nginx:1.26
k set env deploy/web LOG_LEVEL=debug
k set resources deploy/web --limits=cpu=500m,memory=256Mi
k label pod <p> tier=frontend --overwrite
k annotate pod <p> owner=team-a
# label/annotate : même grammaire — suffixe "-" = supprimer, --all / -l pour agir en masse
k label pod <p> tier-                                  # SUPPRIMER le label
k annotate pod <p> owner-                              # SUPPRIMER l'annotation
k label pods --all env=prod                            # en masse

# Patch strategic merge
k patch deploy web -p '{"spec":{"replicas":5}}'
k patch node n1 -p '{"spec":{"unschedulable":true}}'

# Patch JSON
k patch svc web --type=json -p='[{"op":"replace","path":"/spec/type","value":"NodePort"}]'

# Replace vs Apply
k replace -f p.yaml --force                            # recrée le Pod
k apply -f p.yaml                                      # merge déclaratif
```

## 🧨 Delete rapide

```bash
k delete pod <p> --force --grace-period=0              # $now
k delete pod -l app=web
k delete pod --all -n dev
k delete -f manifest.yaml
k delete ns team-a                                     # cascade
```

## 🐚 Exec, logs, cp, port-forward

```bash
k exec -it <p> -c <c> -- bash
k exec <p> -- printenv
k logs <p> -c <c> -f --tail=100 --timestamps
k logs -p <p>                                          # previous crash
k logs -l app=web --max-log-requests=10 --all-containers=true

k cp <p>:/etc/config.yaml ./config.yaml -c <c>
k cp ./data.tgz <p>:/tmp/ -c <c>

k port-forward svc/web 8080:80
k port-forward pod/web-xxx 8080:80
```

## 🔐 Auth & RBAC

```bash
k auth can-i create deploy
k auth can-i list pods --as=alice
k auth can-i list pods --as=system:serviceaccount:dev:bot -n dev
k auth whoami                                          # 1.28+
k create token <sa> --duration=1h                      # token éphémère
```

## 🧭 Diff & dry-run

```bash
k diff -f manifest.yaml                                # diff serveur
k apply -f manifest.yaml --dry-run=server
```

## ⏱️ Watch

```bash
k get pod -w
k get pod --watch-only                                 # que les updates
watch -n 2 'kubectl get pod'                            # externe
```

## 🎁 Bonus — outputs vim/nvim friendly

```bash
# Ne pas ouvrir vi mais un éditeur donné (utile en exam si tu n'aimes pas vi)
export KUBE_EDITOR="nano"
export EDITOR="nano"

# YAML strict (pas de champs vides)
k get pod <p> -o yaml | k neat -                       # kubectl-neat (plugin krew)
```
