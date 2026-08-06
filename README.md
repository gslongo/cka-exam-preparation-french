# 📘 CKA — Préparation examen

> Documentation de révision **digest**, orientée examen, basée sur les cours **LFS158** (Introduction to Kubernetes) et **LFS258** (Kubernetes Fundamentals) de la Linux Foundation.

**Cible** : Certified Kubernetes Administrator (CKA).
**Durée exam** : 2 h · **Score** : ≥ 66 % · **Retake gratuit** : 1 · **Valide** : 2 ans · **Version exam** : K8s v1.35.

> ⚠️ **Disclaimer** : notes de révision **personnelles**, non affiliées à la Linux Foundation ni à la CNCF. Elles reformulent des concepts publics Kubernetes ; **aucun contenu de lab LFS158/LFS258 sous copyright n'est reproduit ici** (les PDF du cours sont exclus via `.gitignore`). Vérifie toujours la [doc officielle](https://kubernetes.io/docs/) et le [curriculum CKA](https://github.com/cncf/curriculum) le jour J.

> ✅ **Entraînement chrono** : [DOMAIN-REVIEW-CHECKLIST.md](DOMAIN-REVIEW-CHECKLIST.md) (50 tâches LFS258 Appendix A)

> 🏆 **Stratégie & Top 15** : [shared/exam-strategy.md](shared/exam-strategy.md) (méthode, timing, bookmarks, PSI)

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
└── lab-setup/                    ← cluster kubeadm local (Vagrant, K8s 1.35)
    ├── README.md
    ├── Vagrantfile
    ├── install-common.sh
    ├── init-cp.sh
    └── join-worker.sh
```

## 🧰 Ressources transverses

- [00-cheatsheet.md](00-cheatsheet.md) — condensé imprimable (à relire J-1)
- [QUESTIONS-EXAMEN.md](QUESTIONS-EXAMEN.md) — questions haute probabilité + solutions
- [PIEGES-EXAMEN.md](PIEGES-EXAMEN.md) — pièges classiques tous chapitres
- [shared/exam-strategy.md](shared/exam-strategy.md) — stratégie examen, Top 15, timing, bookmarks, PSI
- [shared/kubectl-tips.md](shared/kubectl-tips.md) — réflexes kubectl, alias, JSONPath
- [shared/yaml-snippets.md](shared/yaml-snippets.md) — YAML types prêts à copier
- [shared/glossary.md](shared/glossary.md) — glossaire des termes K8s
- [lab-setup/README.md](lab-setup/README.md) — monter un cluster kubeadm local (Vagrant, K8s 1.35)

## 📚 Domaines & pondération CKA (curriculum CNCF)

| # | Domaine | Poids | Fiche |
|---|---|---|---|
| 1 | Cluster Architecture, Installation & Configuration | **25 %** | [01-cluster-architecture.md](01-cluster-architecture.md) |
| 2 | Workloads & Scheduling | **15 %** | [02-workloads-scheduling.md](02-workloads-scheduling.md) |
| 3 | Services & Networking | **20 %** | [03-services-networking.md](03-services-networking.md) |
| 4 | Storage | **10 %** | [04-storage.md](04-storage.md) |
| 5 | Troubleshooting | **30 %** | [05-troubleshooting.md](05-troubleshooting.md) |

> 💡 Priorité de révision = **05 > 01 > 03 > 02 > 04** (ordre de poids décroissant).

## 🗓️ Planning de révision (indicatif)

| Semaine | Focus | Livrables |
|---|---|---|
| S1-S2 | LFS158 (bases) + fiche `01` | Concepts consolidés, cluster kubeadm monté |
| S3-S4 | LFS258 chap. workloads + `02` | Deployments, DaemonSets, scheduling |
| S5 | Networking (`03`) + CNI hands-on | Ingress, NetworkPolicy testés |
| S6 | Storage (`04`) + CSI | PVC static + dynamic |
| S7 | Troubleshooting (`05`) | Logs, events, `crictl`, etcd backup/restore |
| S8 | killer.sh + `00-cheatsheet.md` | Mock exam ×2, timing < 2 h |

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
