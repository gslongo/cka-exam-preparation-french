# 📝 Comment travailler avec l'agent — mémo utilisateur

> Aide-mémoire perso : quelles phrases taper à l'agent pour avancer efficacement dans la préparation CKA.
>
> Le protocole complet (côté agent) est dans [AGENT-INSTRUCTIONS.md § 🤝 Protocole opérationnel](AGENT-INSTRUCTIONS.md).

---

## 🚦 Les 5 types de messages à envoyer

### 1. 📥 Ingérer du contenu de cours

Copie-colle une section (LFS258 la plupart du temps). Format :

```
LFS258 ch.<N> · <Titre section>
<contenu brut, EN ou FR peu importe, mise en forme peu importe>
```

**Ce que fait l'agent** :
1. Identifie la fiche cible (`01` à `05`) et la section
2. Te propose un **preview** : `📄 Fiche · 📍 Emplacement · ⬇️ Bloc à insérer`
3. Attend ton "OK" (ou tes ajustements)
4. Applique + met à jour `LFS258-progress.md`

**Exemple** :
```
LFS258 ch.3 · Kubernetes Architecture
The Kubernetes control plane consists of several components...
[colle ici]
```

---

### 2. ❓ Poser une question de compréhension

Formulation libre. Exemples :
- "Différence entre `podAffinity` et `nodeAffinity` ?"
- "Je comprends pas pourquoi `NodePort` a besoin d'un ClusterIP"
- "Explique-moi le quorum etcd avec 4 membres"

**Ce que fait l'agent** :
- Répond directement en chat (clair et concis)
- Si la réponse mérite d'être conservée → te propose un preview d'ajout à la fiche
- Peut demander "tu veux qu'on ajoute ça à la fiche X ?"

---

### 3. 🧪 Corriger un lab / exercice

Format libre. Utile pour :
- Lab LFS258 avec ton résultat + doute
- Question killer.sh que tu ne comprends pas
- Erreur cluster que tu rencontres

**Exemple** :
```
Lab LFS258 SOLO.6 : j'ai créé le PVC mais il reste Pending. Voici :
<yaml + kubectl describe>
```

**Ce que fait l'agent** :
- Diagnostique
- Explique la cause
- Propose (preview) d'ajouter le piège à `05-troubleshooting.md`

---

### 4. 📊 Demander où tu en es

Tape :
- **"où j'en suis ?"** ou **"statut"** ou **"progression"**

**Ce que fait l'agent** :
- Rapport chapitres LFS258 restants
- Couverture des domaines CKA vs poids exam
- Suggestion prochain focus (ROI max)

L'agent le fait aussi **automatiquement toutes les ~5 ingests**.

---

### 5. 🎯 Forcer un quiz

Tape :
- **"quiz"** → quiz sur le chapitre courant
- **"quiz RBAC"** ou **"teste-moi sur storage"** → quiz ciblé
- **"quiz complet chapitre X"** → 5 questions

**Ce que fait l'agent** :
- 3-5 questions courtes, réponses cachées dans `<details>`
- Basé sur ce que tu as ingéré + ce que le curriculum CKA demande

Sinon, un quiz apparaît **automatiquement** après chaque ingest d'un **gros bloc** (RBAC, scheduling avancé, networking, storage, etcd, upgrade kubeadm, certificats).

---

## 🛡️ Règles côté agent (pour info)

1. **Preview systématique** avant TOUT edit de fiche (`01` à `05`, `00-cheatsheet.md`, `shared/*`)
2. **Edit direct autorisé** (pas de preview) sur : `LFS258-progress.md`, `LFS158-progress.md`, statut 🟢🟡🔴 du `README.md`
3. **Anglais conservé** pour les objets K8s, commandes, termes techniques ; français pour les explications
4. **Aucune paraphrase du cours** — que de la valeur ajoutée (versions récentes, pièges exam, cross-références)
5. **Tutoiement**, jamais de "voici", pas d'emojis à foison

---

## 🎁 Commandes rapides à connaître

| Tu tapes… | L'agent… |
|---|---|
| `LFS258 ch.X · ...` (+ contenu) | Ingest avec preview |
| Question libre en français | Répond + propose éventuellement un ajout |
| `Lab X : ...` (+ contexte) | Diagnostique + propose un piège à ajouter |
| `où j'en suis ?` / `statut` | Rapport progression |
| `quiz` / `quiz <thème>` | Micro-quiz 3-5 Q en `<details>` |
| `OK` (après preview) | L'agent applique |
| `modifie X` (après preview) | L'agent révise le preview |
| `skip` (après preview) | L'agent abandonne l'edit |

---

## 🎓 Signal LFS158 (77 %)

Si tu identifies un concept LFS158 mal maîtrisé (résultat killer.sh, retour de lab, doute) :

```
LFS158 à revoir : <concept>
<optionnel : contexte>
```

L'agent :
1. Réexplique le concept
2. Propose (preview) une entrée dans la fiche CKA appropriée
3. Met à jour `LFS158-progress.md` (colonne 🔁 + log)

---

## 🧯 Si tu es perdu

- `?` ou `aide` → l'agent te ressort ce mémo synthétisé
- `montre le protocole` → affiche la section correspondante de [AGENT-INSTRUCTIONS.md](AGENT-INSTRUCTIONS.md)
- `reset preview` → l'agent oublie le preview en cours et attend un nouveau message
