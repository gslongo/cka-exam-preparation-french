# 📘 CKA — Préparation examen

> Documentation de révision **digest**, orientée examen, basée sur les cours **LFS158** (Introduction to Kubernetes) et **LFS258** (Kubernetes Fundamentals) de la Linux Foundation.

**Cible** : Certified Kubernetes Administrator (CKA).
**Durée exam** : 2 h · **Score** : ≥ 66 % · **Retake gratuit** : 1 · **Valide** : 2 ans · **Version exam** : K8s v1.35.

> ⚠️ **Disclaimer** : notes de révision **personnelles**, non affiliées à la Linux Foundation ni à la CNCF. Elles reformulent des concepts publics Kubernetes ; **aucun contenu de lab LFS158/LFS258 sous copyright n'est reproduit ici** (les PDF du cours sont exclus via `.gitignore`). Vérifie toujours la [doc officielle](https://kubernetes.io/docs/) et le [curriculum CKA](https://github.com/cncf/curriculum) le jour J.

> ✅ **Entraînement chrono** : [DOMAIN-REVIEW-CHECKLIST.md](DOMAIN-REVIEW-CHECKLIST.md) (50 tâches LFS258 Appendix A)

> 🏆 **Stratégie & Top 15** : [shared/exam-strategy.md](shared/exam-strategy.md) (méthode, timing, bookmarks, PSI)

> 🎯 **Examens blancs auto-corrigés** : [exam-01](lab-setup/mock-exam/exam-01/EXAM.md) (intermédiaire) · [exam-02](lab-setup/mock-exam/exam-02/EXAM.md) (**avancé**) · [exam-03](lab-setup/mock-exam/exam-03/EXAM.md) (**expert — drills killer.sh**) — chrono + correction `grade.sh`

> 🧪 **Labs thématiques auto-corrigés** : [Services · Ingress · Gateway API](lab-setup/labs/lab-services-ingress-gateway/LAB.md) · [Stockage · ConfigMap/Secrets · Sidecars](lab-setup/labs/lab-storage-config-multicontainer/LAB.md) · [🔧 Troubleshooting transverse](lab-setup/labs/lab-troubleshooting/LAB.md) · [🛠️ Cluster & etcd](lab-setup/labs/lab-cluster-maintenance/LAB.md) · [📦 Workloads & Scheduling](lab-setup/labs/lab-workloads-scheduling/LAB.md) — un sujet en profondeur (100 pts, seuil 75 %)

> 🇬🇧 **Labs & examens blancs en anglais (volontaire)** : les énoncés (`LAB.md` / `EXAM.md`), les solutions et les correcteurs des **labs thématiques** et des **examens blancs** sont **volontairement rédigés en anglais**, dans le style des énoncés officiels de la CKA — pour t'habituer au vocabulaire et à la formulation le jour J. **Tout le reste du dépôt reste en français** (fiches de révision, stratégie, glossaire, checklists).

> 🧭 **Par où commencer selon ton niveau** : [parcours express](#-parcours-express-selon-ton-niveau) (« débutant complet », « managé/cloud EKS·GKE·AKS » ou « K8s déjà avancé »)

---

## 🗺️ Arborescence

```
CKA/                              ← workspace (ce dossier)
├── README.md                     ← index (ce fichier)
├── AGENT-INSTRUCTIONS.md         ← règles pour l'agent IA          (local — .gitignore)
├── HOWTO.md                      ← mémo : comment interagir avec l'agent
├── TOPICS-A-TRAVAILLER.md        ← points faibles à retravailler (vivant)   (local — .gitignore)
├── QUESTIONS-EXAMEN.md           ← questions haute probabilité + solutions (vivant)
├── PIEGES-EXAMEN.md              ← pièges classiques tous chapitres (vivant)
├── DOMAIN-REVIEW-CHECKLIST.md    ← 50 tâches d'entraînement chrono (LFS258 Appendix A)
├── LFS258-progress.md            ← suivi + scores perso              (local — .gitignore)
├── 00-cheatsheet.md              ← condensé imprimable (J-1)
├── 01-cluster-architecture.md    ← 25 %
├── 02-workloads-scheduling.md    ← 15 %
├── 03-services-networking.md     ← 20 %
├── 04-storage.md                 ← 10 %
├── 05-troubleshooting.md         ← 30 %
├── materials/                    ← PDF de labs LF (copyright)        (local — .gitignore)
├── shared/
│   ├── kubectl-tips.md
│   ├── yaml-snippets.md
│   ├── exam-strategy.md
│   └── glossary.md
└── lab-setup/                    ← cluster kubeadm local (Vagrant, K8s 1.34 → upgrade 1.35)
    ├── README.md
    ├── Vagrantfile
    ├── install-common.sh
    ├── init-cp.sh
    ├── join-worker.sh
    ├── mock-exam/                 ← examens blancs auto-corrigés (un dossier par sujet : exam-01/, exam-02/, exam-03/)
    └── labs/                      ← labs thématiques ciblés (ex. lab-services-ingress-gateway/)
```

## 📚 Domaines & pondération CKA (curriculum CNCF)

| # | Domaine | Poids | Fiche |
|---|---|---|---|
| 1 | Cluster Architecture, Installation & Configuration | **25 %** | [01-cluster-architecture.md](01-cluster-architecture.md) |
| 2 | Workloads & Scheduling | **15 %** | [02-workloads-scheduling.md](02-workloads-scheduling.md) |
| 3 | Services & Networking | **20 %** | [03-services-networking.md](03-services-networking.md) |
| 4 | Storage | **10 %** | [04-storage.md](04-storage.md) |
| 5 | Troubleshooting | **30 %** | [05-troubleshooting.md](05-troubleshooting.md) |

> 💡 Priorité de révision = **05 > 01 > 03 > 02 > 04** (ordre de poids décroissant).

## 🧭 Parcours express selon ton niveau

> Le CKA est un examen d'**administrateur** : il teste surtout ce que les offres managées **cachent** (control plane, `etcd`, static pods, `kubelet`, réseau bas niveau). Choisis ton point d'entrée selon ton profil.

### 0️⃣ Tu pars de zéro (aucune notion Kubernetes)

Avant l'admin, il faut les **fondations**. Objectif : comprendre *ce qu'est* Kubernetes et manipuler les objets de base **avant** d'attaquer la couche control plane.

1. **Bases conteneurs d'abord** : assure-toi de comprendre **image / conteneur / registry** (Docker ou `nerdctl`). K8s orchestre des conteneurs — sans ce socle, tout le reste reste abstrait.
2. **LFS158 — Introduction to Kubernetes** (edX, **gratuit**) : le cours d'entrée. Architecture (control plane vs nodes), Pods, vocabulaire. Garde le [glossaire](shared/glossary.md) ouvert en parallèle.
3. **Fiche 01 en *lecture de découverte*** → [01-cluster-architecture.md](01-cluster-architecture.md) : repère les composants (`apiserver`, `etcd`, `scheduler`, `controller-manager`, `kubelet`, `kube-proxy`) et comment ils s'emboîtent. Ne cherche pas encore à tout retenir.
4. **Monte le lab kubeadm tôt** → [lab-setup/README.md](lab-setup/README.md) : rien ne remplace un vrai cluster sous la main pour ancrer les concepts.
5. **Objets de base**, dans l'ordre d'apprentissage : Pods → Deployments/ReplicaSets → Services → namespaces → ConfigMap/Secret. Fiches [02](02-workloads-scheduling.md) puis [03](03-services-networking.md).
6. **Réflexes kubectl dès le départ** → [shared/kubectl-tips.md](shared/kubectl-tips.md) : `get`/`describe`/`logs`/`explain`, génération de YAML avec `--dry-run=client -o yaml`, alias `k`/`$do`/`$now`.
7. **Puis Storage** [04](04-storage.md) **et Troubleshooting** [05](05-troubleshooting.md), une fois les objets de base assimilés.
8. **Bascule ensuite sur le parcours 1️⃣** ci-dessous pour la mise en condition examen (le lab est déjà monté → tu gagnes du temps).

> ⏱️ Compte plus de temps ici que sur les autres parcours : vise la **compréhension** avant la vitesse. Premier jalon concret = déployer un Pod + Service et lire leurs `describe`/`logs` sans hésiter.

### 1️⃣ Tu as déjà les notions K8s — ou tu ne bosses qu'en managé (EKS / GKE / AKS)

Tu maîtrises `kubectl`, Deployments, Services… mais le managé t'a masqué la couche admin. **Comble ce delta d'abord** — c'est là que se joue l'examen.

1. **Monte le lab kubeadm** → [lab-setup/README.md](lab-setup/README.md). LE différenciateur : tu touches enfin le control plane, `etcd`, les static pods, le `kubelet`.
2. **Fiche 01 — Cluster Architecture** en priorité absolue → [01-cluster-architecture.md](01-cluster-architecture.md) : `kubeadm` init/upgrade, **etcd backup/restore**, RBAC, kubeconfig, static pods (≈ tout ce que le cloud gère à ta place).
3. **Fiche 05 — Troubleshooting** → [05-troubleshooting.md](05-troubleshooting.md) : logs, events, `crictl`, node/`kubelet` down, certificats. **30 %** de l'exam.
4. **Fiche 03 — Services & Networking** → [03-services-networking.md](03-services-networking.md) : CNI, `kube-proxy`, **NetworkPolicy**, Ingress — le réseau « à la main », pas le load-balancer managé.
5. **Révision rapide** de ce que tu connais déjà : [02-workloads-scheduling.md](02-workloads-scheduling.md) + [04-storage.md](04-storage.md).
6. **Vitesse** : [00-cheatsheet.md](00-cheatsheet.md) + [shared/kubectl-tips.md](shared/kubectl-tips.md) (alias `k`, `$do`, `$now`, JSONPath).
7. **Passe l'[examen blanc exam-01](lab-setup/mock-exam/exam-01/EXAM.md)** en conditions réelles (chrono 2 h, correction auto `grade.sh`), puis enchaîne sur l'[exam-02 avancé](lab-setup/mock-exam/exam-02/EXAM.md) quand tu passes l'intermédiaire.
8. **Drills** : [DOMAIN-REVIEW-CHECKLIST.md](DOMAIN-REVIEW-CHECKLIST.md) (50 tâches), puis l'[exam-03](lab-setup/mock-exam/exam-03/EXAM.md) (drills ciblés killer.sh) et enfin **killer.sh** ×2.
9. **J-1** : [shared/exam-strategy.md](shared/exam-strategy.md) (timing, bookmarks, PSI) + [PIEGES-EXAMEN.md](PIEGES-EXAMEN.md).

### 2️⃣ Tu as déjà un niveau K8s avancé

Tu connais l'admin. Il te reste la **vitesse**, le **format** et quelques **mécaniques CKA** à rendre réflexes.

1. **Diagnostic** : attaque directement l'[examen blanc exam-02 avancé](lab-setup/mock-exam/exam-02/EXAM.md) en < 2 h (ou l'[exam-01](lab-setup/mock-exam/exam-01/EXAM.md) pour te caler d'abord sur le format). Le `grade.sh` sort un score /100 **par domaine** → tes trous sont là.
2. **Comble ciblé** les domaines ratés via les fiches concernées ([01](01-cluster-architecture.md) → [05](05-troubleshooting.md)) + [QUESTIONS-EXAMEN.md](QUESTIONS-EXAMEN.md) + [PIEGES-EXAMEN.md](PIEGES-EXAMEN.md).
3. **Automatise les mécaniques CKA** sur le [lab](lab-setup/README.md) jusqu'au réflexe : **etcd backup/restore**, **kubeadm upgrade**, static pods, RBAC, `cordon`/`drain`. → [00-cheatsheet.md](00-cheatsheet.md).
4. **Drills chrono** : [DOMAIN-REVIEW-CHECKLIST.md](DOMAIN-REVIEW-CHECKLIST.md) — vise la vitesse d'exécution, pas la découverte.
5. **Rodage format** : enchaîne l'[exam-03](lab-setup/mock-exam/exam-03/EXAM.md) (drills experts ciblés killer.sh) puis **killer.sh** ×2 (plus dur que le vrai exam) + [shared/exam-strategy.md](shared/exam-strategy.md) (Top 15, alias, gestion des 2 h).
6. **J-1** : [00-cheatsheet.md](00-cheatsheet.md) + [shared/yaml-snippets.md](shared/yaml-snippets.md).

> 🔁 Les trois parcours convergent sur : **lab kubeadm → examen blanc chronométré → drills [exam-03](lab-setup/mock-exam/exam-03/EXAM.md) → killer.sh**. La couche admin (fiche 01) + le troubleshooting (fiche 05) pèsent **55 %** de la note : c'est là qu'un profil « managé » gagne le plus de points.

## 🗓️ Planning de révision (indicatif)

| Semaine | Focus | Livrables |
|---|---|---|
| S1-S2 | LFS158 (bases) + fiche [01](01-cluster-architecture.md) | Concepts consolidés, cluster kubeadm monté |
| S3-S4 | LFS258 chap. workloads + [02](02-workloads-scheduling.md) | Deployments, DaemonSets, scheduling |
| S5 | Networking ([03](03-services-networking.md)) + CNI hands-on | Ingress, NetworkPolicy testés |
| S6 | Storage ([04](04-storage.md)) + CSI | PVC static + dynamic |
| S7 | Troubleshooting ([05](05-troubleshooting.md)) | Logs, events, `crictl`, etcd backup/restore |
| S8 | [exam-03](lab-setup/mock-exam/exam-03/EXAM.md) (drills experts) + killer.sh + [00-cheatsheet.md](00-cheatsheet.md) | Mock exam ×3, timing < 2 h |

## 🧪 Labs thématiques

À la différence des examens blancs (qui balaient tout le programme), les **labs thématiques** creusent **un sujet** en profondeur. Même mécanique auto-corrigée (`LAB.md` + `setup.sh` + `grade.sh` + `solutions/`), sans limite de temps.

| Lab | Contenu | Barème |
|---|---|---|
| **Services · Ingress · Gateway API**<br>[LAB.md](lab-setup/labs/lab-services-ingress-gateway/LAB.md) · [solutions/](lab-setup/labs/lab-services-ingress-gateway/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/labs/lab-services-ingress-gateway/setup.sh) · [grade.sh](lab-setup/labs/lab-services-ingress-gateway/grade.sh) | Exposition du trafic L4→L7 : ClusterIP/NodePort/headless, Service sans selector + Endpoints, réparation de Service, Ingress (host/path, fanout, TLS), Gateway API (HTTPRoute préfixe, header-match, canary pondéré) | 100 pts · ≥ 75 % |
| **Stockage · ConfigMap/Secrets · Sidecars**<br>[LAB.md](lab-setup/labs/lab-storage-config-multicontainer/LAB.md) · [solutions/](lab-setup/labs/lab-storage-config-multicontainer/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/labs/lab-storage-config-multicontainer/setup.sh) · [grade.sh](lab-setup/labs/lab-storage-config-multicontainer/grade.sh) | Persistance & configuration : StorageClass, binding statique PV/PVC, récupération d'un PV `Released` (claimRef), ConfigMap/Secrets (`envFrom`, `secretKeyRef`, volume), `emptyDir` partagé, sidecar natif (initContainer `restartPolicy: Always`) | 100 pts · ≥ 75 % |
| **🔧 Troubleshooting transverse**<br>[LAB.md](lab-setup/labs/lab-troubleshooting/LAB.md) · [solutions/](lab-setup/labs/lab-troubleshooting/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/labs/lab-troubleshooting/setup.sh) · [grade.sh](lab-setup/labs/lab-troubleshooting/grade.sh) | **Tout est cassé, à réparer** — 16 pannes sur les 4 domaines : RBAC, static pod (`cp1`), noeud `w1` cordonné+taint, finalizer `Terminating`, `ImagePull`/`CrashLoop`/`CreateContainerConfigError`, `Pending` (ressources/nodeSelector), readiness, selector/`targetPort`/NetworkPolicy/`dnsPolicy`, PVC `Pending`/manquante. Testé en direct (trafic, DNS) | 100 pts · ≥ 75 % |
| **🛠️ Cluster Maintenance, etcd & Security**<br>[LAB.md](lab-setup/labs/lab-cluster-maintenance/LAB.md) · [solutions/](lab-setup/labs/lab-cluster-maintenance/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/labs/lab-cluster-maintenance/setup.sh) · [grade.sh](lab-setup/labs/lab-cluster-maintenance/grade.sh) | *Domaine 01 (25 %)* — **opérations d'admin** : backup/restore etcd (`etcdctl`/`etcdutl` via `exec`), approbation de CSR client, `kubeadm certs check-expiration`, ClusterRole/Role RBAC (`auth can-i`), `drain` de noeud, static pod sur `cp1` | 100 pts · ≥ 75 % |
| **📦 Workloads & Scheduling**<br>[LAB.md](lab-setup/labs/lab-workloads-scheduling/LAB.md) · [solutions/](lab-setup/labs/lab-workloads-scheduling/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/labs/lab-workloads-scheduling/setup.sh) · [grade.sh](lab-setup/labs/lab-workloads-scheduling/grade.sh) | *Domaine 02 (15 %)* — **build de workloads** : Deployment + scale, stratégie `RollingUpdate`, DaemonSet (tolérations), Job/CronJob, HPA, QoS `Guaranteed`, `nodeSelector`, `nodeAffinity`, taint+toleration, `topologySpreadConstraints`, `PriorityClass` | 100 pts · ≥ 75 % |

## 🎯 Examens blancs CKA

Trois examens blancs complets **auto-corrigés** tournent sur le [lab local](lab-setup/README.md). Chaque sujet vit dans son sous-dossier.

- **exam-01** & **exam-02** — format « vrai CKA » : **16 tâches, 100 pts, seuil 66 %, ~2 h**, pondérés par domaine (Troubleshooting 30 % · Cluster Architecture 25 % · Réseau 20 % · Workloads 15 % · Storage 10 %).
- **exam-03** — format « killer.sh » : **drills ciblés** qui comblent les sujets pointus rencontrés sur killer.sh (mapping ~1:1 avec ses questions), au-delà de ce que couvrent exam-01/02.

Détail des niveaux :

- **exam-01** — niveau intermédiaire : RBAC namespacé, snapshot etcd, static pod, cordon, ConfigMap→env, NodePort, NetworkPolicy simple, PV/PVC…
- **exam-02** — **niveau avancé** : RBAC *cluster-scoped*, scheduling manuel, taints/tolerations, Secret→env, NetworkPolicy *default-deny*, `reclaimPolicy`/`subPath`, troubleshooting moins évident (sonde, dérive de labels, contrainte de placement, Secret manquant).
- **exam-03** — **niveau expert (drills killer.sh)** : extraction kubeconfig, Helm + cert-manager + ClusterIssuer, StatefulSet scale, QoS, **HPA + Kustomize**, PV/PVC monté par Deployment, `kubectl top`, upgrade worker + `kubeadm join`, API depuis un Pod, DaemonSet, anti-affinité multi-conteneurs, **Gateway API** (chemin + en-tête), `kubeadm certs renew`, **NetworkPolicy egress** (enforcement runtime), CoreDNS, `crictl`, introspection etcd, kube-proxy iptables, **Service CIDR** multi-range.

| Sujet | Fichiers |
|---|---|
| **exam-01** (intermédiaire) | [EXAM.md](lab-setup/mock-exam/exam-01/EXAM.md) · [solutions/SOLUTIONS.md](lab-setup/mock-exam/exam-01/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/mock-exam/exam-01/setup.sh) · [grade.sh](lab-setup/mock-exam/exam-01/grade.sh) |
| **exam-02** (avancé) | [EXAM.md](lab-setup/mock-exam/exam-02/EXAM.md) · [solutions/SOLUTIONS.md](lab-setup/mock-exam/exam-02/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/mock-exam/exam-02/setup.sh) · [grade.sh](lab-setup/mock-exam/exam-02/grade.sh) |
| **exam-03** (expert — killer.sh) | [EXAM.md](lab-setup/mock-exam/exam-03/EXAM.md) · [solutions/SOLUTIONS.md](lab-setup/mock-exam/exam-03/solutions/SOLUTIONS.md) · [setup.sh](lab-setup/mock-exam/exam-03/setup.sh) · [grade.sh](lab-setup/mock-exam/exam-03/grade.sh) |

Dans chaque sujet : `EXAM.md` = **questions seules** · `solutions/SOLUTIONS.md` = corrigé (à n'ouvrir **qu'après**) · `setup.sh` = amorce **idempotente** · `grade.sh` = correcteur **automatique** (score + verdict par domaine).

> ▶️ **Mode d'emploi** (commandes `vagrant`) : voir [lab-setup/README.md](lab-setup/README.md).

## 🧰 Ressources transverses

- [00-cheatsheet.md](00-cheatsheet.md) — condensé imprimable (à relire J-1)
- [QUESTIONS-EXAMEN.md](QUESTIONS-EXAMEN.md) — questions haute probabilité + solutions
- [PIEGES-EXAMEN.md](PIEGES-EXAMEN.md) — pièges classiques tous chapitres
- [shared/exam-strategy.md](shared/exam-strategy.md) — stratégie examen, Top 15, timing, bookmarks, PSI
- [shared/kubectl-tips.md](shared/kubectl-tips.md) — réflexes kubectl, alias, JSONPath
- [shared/yaml-snippets.md](shared/yaml-snippets.md) — YAML types prêts à copier
- [shared/glossary.md](shared/glossary.md) — glossaire des termes K8s
- [lab-setup/README.md](lab-setup/README.md) — monter un cluster kubeadm local (Vagrant, init K8s 1.34 → upgrade 1.35 à pratiquer, objectif version exam)
- [lab-setup/mock-exam/exam-01/EXAM.md](lab-setup/mock-exam/exam-01/EXAM.md) — examen blanc auto-corrigé, niveau intermédiaire (16 tâches, `setup.sh` + `grade.sh`)
- [lab-setup/mock-exam/exam-02/EXAM.md](lab-setup/mock-exam/exam-02/EXAM.md) — examen blanc auto-corrigé, **niveau avancé** (RBAC cluster-scoped, taints, NetworkPolicy default-deny, `subPath`…)
- [lab-setup/mock-exam/exam-03/EXAM.md](lab-setup/mock-exam/exam-03/EXAM.md) — examen blanc auto-corrigé, **niveau expert** — drills ciblés killer.sh (Helm/cert-manager, HPA+Kustomize, Gateway API, egress, `crictl`, ServiceCIDR…)
- [lab-setup/labs/lab-services-ingress-gateway/LAB.md](lab-setup/labs/lab-services-ingress-gateway/LAB.md) — **lab thématique** auto-corrigé : Services · Ingress · Gateway API (100 pts, objectif ≥ 75 %, `setup.sh` + `grade.sh`)
- [lab-setup/labs/lab-storage-config-multicontainer/LAB.md](lab-setup/labs/lab-storage-config-multicontainer/LAB.md) — **lab thématique** auto-corrigé : Stockage · ConfigMap/Secrets · Sidecars (100 pts, objectif ≥ 75 %, `setup.sh` + `grade.sh`)
- [lab-setup/labs/lab-troubleshooting/LAB.md](lab-setup/labs/lab-troubleshooting/LAB.md) — **lab thématique** auto-corrigé : 🔧 Troubleshooting transverse — 16 pannes tous domaines à diagnostiquer et réparer (100 pts, objectif ≥ 75 %, `setup.sh` + `grade.sh`)
- [lab-setup/labs/lab-cluster-maintenance/LAB.md](lab-setup/labs/lab-cluster-maintenance/LAB.md) — **lab thématique** auto-corrigé : 🛠️ Cluster Maintenance, etcd & Security — backup/restore etcd, approbation CSR, RBAC, drain de noeud, static pod (domaine 01) (100 pts, objectif ≥ 75 %, `setup.sh` + `grade.sh`)
- [lab-setup/labs/lab-workloads-scheduling/LAB.md](lab-setup/labs/lab-workloads-scheduling/LAB.md) — **lab thématique** auto-corrigé : 📦 Workloads & Scheduling — Deployments/rollout, DaemonSet/Job/CronJob, HPA, QoS, nodeSelector/affinity/taints/topology spread/PriorityClass (domaine 02) (100 pts, objectif ≥ 75 %, `setup.sh` + `grade.sh`)

## 🔗 Ressources autorisées jour J

- `https://kubernetes.io/docs/`
- `https://kubernetes.io/blog/`
- `https://github.com/kubernetes/`

> ⚠️ Aucune autre URL. Bookmarks à préparer dans [shared/exam-strategy.md](shared/exam-strategy.md).

---

## 📄 Licence & attribution

- **Notes personnelles** publiées à titre éducatif — reformulation de concepts publics Kubernetes.
- **Non affilié** à la Linux Foundation, la CNCF ou le programme CKA.
- Le matériel de cours **LFS158/LFS258 sous copyright** (PDF de labs) n'est **pas** inclus dans ce dépôt (`.gitignore`).
- « Kubernetes » et « CKA » sont des marques de la Linux Foundation / CNCF.
- Contenu libre de réutilisation à des fins de révision. Aucune garantie d'exactitude — **la doc officielle fait foi**.

## 📌 Sources faisant autorité

- **LFS158** — Introduction to Kubernetes (edX, gratuit)
- **LFS258** — Kubernetes Fundamentals (Linux Foundation, payant)
- [CKA Curriculum GitHub](https://github.com/cncf/curriculum)
- [Kubernetes docs](https://kubernetes.io/docs/)
- [killer.sh](https://killer.sh/) — 2 sessions incluses avec l'inscription CKA (activer 36 h avant)
