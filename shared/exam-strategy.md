# 🎯 Stratégie examen CKA

> **Version exam actuelle : Kubernetes v1.35** (vérifié LF, 2026-07-24).
> L'environnement CKA suit la dernière minor upstream avec **~4-8 semaines de retard**.
> ⚠️ La dernière stable upstream (ex : 1.36) n'est PAS forcément la version exam. Toujours revérifier la date d'exam approchant : docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad
> Format : 2 h · 15-20 tâches pratiques · **passage 66 %** · 1 retake gratuit · killer.sh (2 sessions 36 h).

## 🏆 Top 15 à savoir absolument

> Synthèse priorisée (poids × fréquence × temps perdu si non maîtrisé). Le vrai tueur = **le temps**.

#### ⚙️ Mécanique & vitesse

1. `kubectl` impératif + `--dry-run=client -o yaml` > YAML from scratch. Objectif <60 s/objet.
2. Setup 20 s : `alias k=kubectl`, `export do='--dry-run=client -o yaml'`, completion bash.
3. `kubectl explain <res>.<champ>` pour les champs sans quitter le terminal.
4. Doc kubernetes.io au **search**, pas aux bookmarks perso (secure browser).
5. `kubectl config use-context` **avant chaque question** + verrouiller `-n <ns>`. Oubli = 0 point.

#### 🏗️ Cluster Architecture (25%)

6. **etcd backup + restore** (quasi garanti) : `snapshot save/restore --data-dir` + repointer le static pod.
7. **kubeadm upgrade** (quasi garanti) : `drain` → apply/upgrade node → kubelet+kubectl (apt) → `uncordon`.
8. **RBAC** : Role/Binding via `kubectl create role/rolebinding`, test `auth can-i --as=`.

#### 📦 Workloads (15%)

9. Rollout : `set image`, `rollout status/undo/history`, `scale --replicas`.
10. Scheduling : `nodeSelector`, taints/tolerations, affinity ; requests/limits → `FailedScheduling`.

#### 🌐 Services & Networking (20%)

11. Service types + **`kubectl get endpoints`** (réflexe debug selector mismatch).
12. NetworkPolicy : `podSelector`+`namespaceSelector` items `-` séparés = **OR**, même item = **AND**.
13. Ingress (host/path, `pathType`, `ingressClassName`) + debug CoreDNS (`busybox nslookup`).

#### 💾 Storage (10%) & 🔧 Troubleshooting (30%)

14. PV/PVC/StorageClass : accessModes, reclaimPolicy, volumeMode ; PVC `Pending` = pas de PV/SC compatible.
15. Méthode systématique **`describe` → `logs` → `events`** ; node down → `journalctl -u kubelet` ; CP down → `/etc/kubernetes/manifests/` + `crictl`.

> Règle au-dessus de tout : *Understand = create + configure + troubleshoot + delete*, **chrono en main**. Entraînement = [DOMAIN-REVIEW-CHECKLIST.md](../DOMAIN-REVIEW-CHECKLIST.md) puis **killer.sh**.

## 🧭 Comment lire le curriculum CNCF

> Dans le curriculum, **« Understand X »** ne veut PAS dire « savoir que ça existe ».
> LF le définit par **5 verbes** — attends-toi à être testé sur chacun :
> **create · configure · integrate · update · troubleshoot**.
> Ex. « Understand Services » = créer un Service, le configurer, le brancher à un
> Deployment, le modifier, et débugger ses endpoints.

Le Domain Review (Appendix A de LFS258) fournit ~50 tâches à faire **au chrono**
pour couvrir chaque item ; **killer.sh** reste la référence de difficulté.

## 📅 Avant l'exam

### J-30 à J-14
- Terminer LFS158 + LFS258
- Toutes les fiches (`01` → `05`) marquées 🟢
- Configurer un cluster local (`kind` ou `kubeadm` sur 2 VMs) pour la pratique
- Sur chaque fiche : refaire les YAML **sans les copier**

### J-14 à J-7
- **killer.sh session 1** (dispo dès inscription, 36 h d'accès) → ne pas paniquer, le vrai exam est plus facile
- Refaire les questions ratées **jusqu'à 100 %**
- Chronométrer : objectif ≤ 6 min / question sur les rapides, ≤ 12 min sur les lourdes

### J-7 à J-1
- **killer.sh session 2** en conditions
- Imprimer `00-cheatsheet.md` et le relire
- Préparer les bookmarks navigateur (voir plus bas)
- Vérifier setup PSI : caméra, ID, pièce dégagée

### J-1
- **Ne pas coder**. Relire cheatsheet + fiche `05-troubleshooting`.
- Vérifier email PSI, timezone, heure exacte
- Se coucher tôt

## 🔖 Bookmarks à préparer

Le navigateur exam autorise les bookmarks vers `kubernetes.io`, `kubernetes.io/blog`, `github.com/kubernetes`.

### Bookmarks essentiels

| Nom | URL | Usage |
|---|---|---|
| kubectl reference | https://kubernetes.io/docs/reference/kubectl/kubectl/ | Fallback commandes |
| kubectl conventions | https://kubernetes.io/docs/reference/kubectl/conventions/ | `--dry-run`, JSONPath |
| Pods | https://kubernetes.io/docs/concepts/workloads/pods/ | ref containers |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ | strategy, rollout |
| StatefulSets | https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/ | volumeClaimTemplates |
| DaemonSets | https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/ | tolerations |
| Services | https://kubernetes.io/docs/concepts/services-networking/service/ | tous types |
| Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ | pathType, TLS |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ | patterns |
| ConfigMaps | https://kubernetes.io/docs/concepts/configuration/configmap/ | envFrom |
| Secrets | https://kubernetes.io/docs/concepts/configuration/secret/ | tls, docker-registry |
| PersistentVolumes | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ | reclaim, accessModes |
| StorageClasses | https://kubernetes.io/docs/concepts/storage/storage-classes/ | provisioners |
| RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ | verbs, aggregation |
| kubeadm | https://kubernetes.io/docs/reference/setup-tools/kubeadm/ | init, join, upgrade |
| **kubeadm upgrade** | https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/ | procédure exacte |
| **etcd backup/restore** | https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster | procédure exacte |
| Debug Pods | https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/ | ephemeral debug |
| Debug Services | https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/ | endpoints |
| Taints & Tolerations | https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ | effets |
| Node Affinity | https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ | required vs preferred |
| Cheatsheet officielle | https://kubernetes.io/docs/reference/kubectl/quick-reference/ | rappel `$do` |

> 💡 Organiser les bookmarks par **domaine CKA** (01, 02…) pour retrouver vite pendant l'exam.

## 🧭 Méthode pendant l'exam

### Setup initial (30 s)

```bash
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

### Pour CHAQUE question

1. **Lire la question 2 fois** — repérer le **contexte** (`kubectl config use-context <name>`)
2. **Toujours** exécuter `kubectl config use-context ...` **avant** toute action
3. Repérer le **namespace** (`-n <ns>`) mentionné → verrouiller : `k config set-context --current --namespace=<ns>`
4. Si Q "coûteuse" (upgrade, etcd, network) → **flag et passe** si tu bloques > 2 min sur setup
5. Vérifier ton travail : `k get <res>` + `k describe` + `k logs`

### Priorisation en 2 h

- Score cible : **80 %** (garde marge sur 66 %)
- Question 4 % ? Skip si bloqué 5 min.
- Question 12 % ? Investis jusqu'à 20 min.
- **Toujours revenir** aux questions flaggées à la fin.

### Erreurs qui coûtent cher

- Oublier de switcher le contexte → tu modifies le mauvais cluster (0 point)
- Oublier `-n <ns>` → ressource au mauvais endroit
- Créer une ressource dans le mauvais namespace = 0 point, même si YAML parfait
- Confondre `Deployment` et `DeploymentConfig` (OpenShift, pas K8s)
- Écrire à la main un YAML complexe au lieu d'utiliser `$do`

## 🧪 Environnement PSI Bridge

- **Terminal navigateur** (Chrome/Chromium requis)
- Un onglet unique autorisé : la doc K8s
- Copier-coller `Ctrl+Ins` / `Shift+Ins` (⚠️ pas `Ctrl+C/V` dans le terminal Linux emulé — dépend du browser terminal)
- **Multi-cluster** : chaque question a son contexte kubectl. **VÉRIFIE avant de taper**.
- Bureau physique **complètement dégagé**, mur derrière visible caméra, ID valide sur place.

## 🧯 Si ça se passe mal

- Perte de connexion : la session se met en pause, le temps continue en général. Reconnecte-toi vite.
- Bug cluster : signale au proctor via chat — souvent une manip cluster restore possible.
- Bug ressource : `kubeadm reset` **est autorisé** si la question le demande.
- Retake : **1 gratuit** inclus dans les 12 mois → utilise-le si score < 60 %.

## 📈 Après l'exam

- Résultats en **24 h**
- Certif valide **3 ans**, renouvelable par re-passage
- Si échec : identifie le domaine faible via feedback (poids par domaine), refais killer.sh en priorité
