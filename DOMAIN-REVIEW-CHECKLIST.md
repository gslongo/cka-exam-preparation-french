# ✅ Domain Review — Checklist d'entraînement chrono

> **Source : LFS258 Appendix A (lab V2026-06-03) — Exercise A.3 « Practicing Skills ».**
> C'est le meilleur asset d'auto-test trouvé dans le cours : 50 tâches à réaliser **sans qu'on te dise quoi taper**, exactement l'esprit de l'exam.
> Objectif : les faire **chrono en main**, deux fois, jusqu'à ce que ça coule tout seul.
>
> ⚠️ *Rappel de LFS258 lui-même : « practice creating, integrating, and troubleshooting all domain items at speed »* et *« vérifie toujours le curriculum CNCF à jour, il peut changer »*.
> ⚠️ Les items renvoient à des fichiers YAML fournis dans le tarball du cours (`review1.yaml`, `review2.yaml`, `review4.yaml`, `review5.yaml`, `review6.yaml`, `design-pod1`). Sur ta machine LF hosted, retrouve-les via `find ~ -name 'review*.yaml'`.

_Dernière mise à jour : 2026-07-30_

---

<details open>
<summary>📑 Sommaire</summary>

- [🎯 Domain Review Items (compétences officielles, copiées du curriculum CNCF)](#-domain-review-items-compétences-officielles-copiées-du-curriculum-cncf)
- [🏋️ Exercise A.3 — 50 tâches (checklist chrono)](#️-exercise-a3--50-tâches-checklist-chrono)
  - [Bloc 1 · Pods, deployments, troubleshooting YAML (1-13)](#bloc-1--pods-deployments-troubleshooting-yaml-1-13)
  - [Bloc 2 · Secrets, rollout, storage NFS (14-24)](#bloc-2--secrets-rollout-storage-nfs-14-24)
  - [Bloc 3 · Services & NetworkPolicy (25-29)](#bloc-3--services--networkpolicy-25-29)
  - [Bloc 4 · securityContext & troubleshooting (30-34)](#bloc-4--securitycontext--troubleshooting-30-34)
  - [Bloc 5 · RBAC + ServiceAccount + token (35-39)](#bloc-5--rbac--serviceaccount--token-35-39)
  - [Bloc 6 · Services types, CoreDNS, Ingress (40-47)](#bloc-6--services-types-coredns-ingress-40-47)
  - [Bloc 7 · etcd + upgrade + scheduler (48-50)](#bloc-7--etcd--upgrade--scheduler-48-50)
- [🔗 Recoupements avec les fiches](#-recoupements-avec-les-fiches)

</details>

## 🎯 Domain Review Items (compétences officielles, copiées du curriculum CNCF)

> LFS258 recopie ici les domaines du PDF officiel. À croiser avec le curriculum CKA v1.35 réel (poids : Cluster Arch 25 %, Workloads 15 %, Services & Net 20 %, Storage 10 %, Troubleshooting 30 %).

- **Cluster Architecture, Installation & Configuration** → fiche [01](01-cluster-architecture.md)
  - Manage RBAC · Kubeadm install basic cluster · **HA cluster** · provision infra · **version upgrade (kubeadm)** · **etcd backup & restore**
- **Workloads & Scheduling** → fiche [02](02-workloads-scheduling.md)
  - Deployments + rolling updates/rollbacks · ConfigMaps & Secrets · scaling · self-healing primitives · resource limits → scheduling · **manifest mgmt & templating tools** (Kustomize/Helm)
- **Services & Networking** → fiche [03](03-services-networking.md)
  - Host networking · Pod-to-Pod · ClusterIP/NodePort/LoadBalancer + endpoints · Ingress controllers & resources · **CoreDNS** · choisir un plugin CNI
- **Storage** → fiche [04](04-storage.md)
  - StorageClasses, PV · volumeMode, accessModes, reclaim policies · PVC · applis avec stockage persistant
- **Troubleshooting** (30 % — le plus gros) → fiche [05](05-troubleshooting.md)
  - Logs cluster/node · monitoring applis · stdout/stderr containers · app failure · **cluster component failure** · **networking**

---

## 🏋️ Exercise A.3 — 50 tâches (checklist chrono)

> Coche au fur et à mesure. La colonne **Fiche** te renvoie à la solution/pattern. La colonne **Exam** signale la valeur examen (⭐ = estimation perso, pas une fuite).

### Bloc 1 · Pods, deployments, troubleshooting YAML (1-13)

- [ ] **1.** `find ~ -name review1.yaml`, copier chez soi, `kubectl create -f`, vérifier Running, **corriger les erreurs** (`kubectl describe`). → [05](05-troubleshooting.md) ⭐⭐⭐
- [ ] **2.** Nettoyer : `kubectl delete -f review1.yaml`.
- [ ] **3.** `review2.yaml` : deployment cassé à réparer, **2 conteneurs Ready** (web:80, proxy:8080). → [05](05-troubleshooting.md) ⭐⭐
- [ ] **4.** Voir la page par défaut du serveur web + vérifier le log `GET / HTTP/1.1 200` dans le container. → [05](05-troubleshooting.md)
- [ ] **5.** `review4.yaml` : créer un pod, vérifier Running.
- [ ] **6.** Éditer le pod pour qu'il tourne **seulement sur worker** via `nodeSelector`. → [02](02-workloads-scheduling.md) ⭐⭐
- [ ] **7.** Déterminer les **requests CPU/mémoire** de `design-pod1`.
- [ ] **8.** Éditer les resources : **limit CPU = 2× le request** (indice : soustraire .22). → [02](02-workloads-scheduling.md)
- [ ] **9.** Augmenter la **memory limit** jusqu'à ce que le pod tienne Running ≥ 1 min (trouver le minimum). → [02](02-workloads-scheduling.md) — piège OOMKilled
- [ ] **10.** `review5.yaml` : créer plusieurs pods avec labels variés.
- [ ] **11.** Supprimer **uniquement** les pods `--selector <clé>=tux` (la moitié). → [02](02-workloads-scheduling.md) ⭐⭐
- [ ] **12.** **CronJob** busybox `sleep 30`, toutes les **3 min** ; puis reconfigurer : « 10 min après l'heure actuelle, **chaque lundi** » (ex. 14:14 → `24 14 * * 1`). → [02](02-workloads-scheduling.md) ⭐⭐
- [ ] **13.** Tout nettoyer (garder éventuellement le CronJob pour le voir se déclencher).

### Bloc 2 · Secrets, rollout, storage NFS (14-24)

- [ ] **14.** `Secret` `specialofday`, clé `entree` = `meatloaf` (`--from-literal`). → [04](04-storage.md) / [02](02-workloads-scheduling.md) ⭐⭐
- [ ] **15.** Deployment `foodie` image nginx.
- [ ] **16.** Monter le secret `specialofday` **comme volume** sous `/food/`. → [04](04-storage.md) ⭐⭐
- [ ] **17.** `exec` bash dans le pod `foodie` → vérifier le montage du secret.
- [ ] **18.** Update image → `nginx:1.12.1-alpine`, vérifier le rollout. → [02](02-workloads-scheduling.md) ⭐⭐
- [ ] **19.** **Rollback** → revérifier l'image nginx stable en cours. → [02](02-workloads-scheduling.md) ⭐⭐
- [ ] **20.** PV NFS **200M** `reviewvol` (serveur NFS du lab). → [04](04-storage.md) ⭐⭐
- [ ] **21.** PVC `reviewpvc` qui utilise `reviewvol`. → [04](04-storage.md) ⭐⭐
- [ ] **22.** Éditer le deployment pour utiliser la PVC, montée sous `/newvol`. → [04](04-storage.md)
- [ ] **23.** `exec` bash → vérifier le montage du volume.
- [ ] **24.** Tout nettoyer.

### Bloc 3 · Services & NetworkPolicy (25-29)

- [ ] **25.** Deployment nginx.
- [ ] **26.** Service **LoadBalancer** l'exposant, tester. → [03](03-services-networking.md) ⭐⭐
- [ ] **27.** **NetworkPolicy** `netblock` qui **bloque tout** le trafic vers ces pods ; tester que tout est bloqué. → [03](03-services-networking.md) ⭐⭐⭐
- [ ] **28.** Pod nginx, s'assurer que le trafic l'atteint.
- [ ] **29.** Update `netblock` → **autoriser seulement le port 80** ; tester l'accès à la page nginx. → [03](03-services-networking.md) ⭐⭐⭐

### Bloc 4 · securityContext & troubleshooting (30-34)

- [ ] **30.** `review6.yaml` → créer le pod (`securityreview`).
- [ ] **31.** Voir le status du pod.
- [ ] **32.** Diagnostiquer : `get` / `describe` / `logs`. → [05](05-troubleshooting.md) ⭐⭐⭐
- [ ] **33.** Trouver l'**uid du user nginx** dans le container. → [02](02-workloads-scheduling.md) piège #34
- [ ] **34.** Mettre le `securityContext` correct pour que le serveur web lise ses fichiers de conf. → [02](02-workloads-scheduling.md) ⭐⭐

### Bloc 5 · RBAC + ServiceAccount + token (35-39)

- [ ] **35.** `serviceAccount` `securityaccount`. → [01](01-cluster-architecture.md) ⭐⭐
- [ ] **36.** `ClusterRole` `secrole` : **create, delete, list** de pods sur **tous les apiGroups**. → [01](01-cluster-architecture.md) ⭐⭐
- [ ] **37.** Bind le ClusterRole au ServiceAccount. → [01](01-cluster-architecture.md) ⭐⭐
- [ ] **38.** Extraire le **token** du SA dans `/tmp/securitytoken` (uniquement la valeur, chaîne `eyJh…`). → [01](01-cluster-architecture.md) ⭐⭐
- [ ] **39.** Nettoyer.

### Bloc 6 · Services types, CoreDNS, Ingress (40-47)

- [ ] **40.** Pod `webone` nginx, expose port 80.
- [ ] **41.** Service `webone-svc` accessible **depuis l'extérieur** (NodePort/LB). → [03](03-services-networking.md) ⭐⭐
- [ ] **42.** Ajouter les **selectors** pod+service pour que l'IP du service serve le contenu web.
- [ ] **43.** Changer le type → **ClusterIP** (accessible seulement dans le cluster) ; tester que l'extérieur ne marche plus. → [03](03-services-networking.md)
- [ ] **44.** Pod `webtwo` image `wlniao/website` + service `webtwo-svc` interne au cluster (pages par défaut distinctes).
- [ ] **45.** Tester les **noms DNS** + vérifier que **CoreDNS** fonctionne (`dig`, FQDN). → [03](03-services-networking.md) ⭐⭐
- [ ] **46.** **Ingress** : `webone.com` → nginx, `webtwo.org` → wlniao/website (peu importe le controller). → [03](03-services-networking.md) ⭐⭐⭐
- [ ] **47.** Nettoyer.

### Bloc 7 · etcd + upgrade + scheduler (48-50)

- [ ] **48.** Installer un cluster en version **antérieure récente**, **backup etcd**, puis **upgrade complet** du cluster. → [01](01-cluster-architecture.md) ⭐⭐⭐ (etcd backup + kubeadm upgrade = quasi garantis)
- [ ] **49.** Créer un pod busybox **sans passer par le scheduler** (`spec.nodeName`). → [02](02-workloads-scheduling.md) piège T9/T11 ⭐⭐
- [ ] **50.** Continuer à créer/intégrer/troubleshooter jusqu'à couvrir **chaque item de domaine**.

---

## 🔗 Recoupements avec les fiches

| Item(s) A.3 | Concept | Déjà couvert |
|---|---|---|
| 1-4, 30-32 | Troubleshoot YAML / app failure | ✅ [05](05-troubleshooting.md) |
| 6, 49 | `nodeSelector` / `nodeName` bypass scheduler | ✅ [02](02-workloads-scheduling.md) L467, [PIEGES](PIEGES-EXAMEN.md) T9/T11 |
| 8-9 | resources requests/limits, OOMKilled | ✅ [02](02-workloads-scheduling.md) |
| 11 | delete par `--selector` | ✅ [02](02-workloads-scheduling.md) |
| 12 | CronJob schedule cron | ✅ [02](02-workloads-scheduling.md) |
| 14-17 | Secret monté en volume | ✅ [04](04-storage.md) |
| 18-19 | rollout / rollback | ✅ [02](02-workloads-scheduling.md) |
| 20-23 | PV/PVC NFS | ✅ [04](04-storage.md) |
| 27-29 | NetworkPolicy block-all → allow port | ✅ [03](03-services-networking.md), [PIEGES](PIEGES-EXAMEN.md) N3/N4 |
| 33-34 | securityContext uid nginx | ✅ [02](02-workloads-scheduling.md) piège #34 |
| 35-38 | SA + ClusterRole + bind + token | ✅ [01](01-cluster-architecture.md) |
| 40-46 | Service types + CoreDNS + Ingress | ✅ [03](03-services-networking.md) |
| 48 | etcd backup + upgrade | ✅ [01](01-cluster-architecture.md), [QUESTIONS](QUESTIONS-EXAMEN.md) Q1/Q2 |

> Conclusion : la checklist ne révèle **aucun trou** dans les fiches — elle sert d'**entraînement chrono** pour tout enchaîner sans réfléchir. Le vrai test blanc reste **killer.sh** (2 sessions incluses avec l'inscription).
