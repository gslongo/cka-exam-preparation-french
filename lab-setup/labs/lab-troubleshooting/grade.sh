#!/usr/bin/env bash
# grade.sh — correction automatique du lab « Troubleshooting transverse ».
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/grade.sh"
#
# Lecture seule : AUCUNE modification. Affiche PASS/FAIL par tâche (avec le symptôme
# observé, jamais la solution), sous-total par domaine et score /100 (objectif ≥ 75 %).
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }
jp()   { kubectl "$@" 2>/dev/null; }

# ══════════════════════════════════════════════════════════════════════════════
dom ARCH 28 "🏛️  Cluster Architecture & Nodes"

# A1 — RBAC réparé (8)
d=ARCH
can_list=$(jp auth can-i list pods --as=system:serviceaccount:ts-arch:deploy-bot -n ts-arch)
can_del=$(jp auth can-i delete pods --as=system:serviceaccount:ts-arch:deploy-bot -n ts-arch)
if [ "$can_list" = "yes" ] && [ "$can_del" = "no" ]; then
  pass 8 "A1 RBAC — deploy-bot peut lister mais pas supprimer les pods" $d
else
  r=""
  [ "$can_list" = "yes" ] || r+="ne peut pas 'list' les pods; "
  [ "$can_del" = "no" ]   || r+="peut 'delete' les pods (droits trop larges); "
  fail 8 "A1 RBAC — deploy-bot doit pouvoir 'list' mais pas 'delete' les pods" $d "${r%; }"
fi

# A2 — static pod réparé sur cp1 (8)
d=ARCH
phase=$(jp get pod ts-static-cp1 -n default -o jsonpath='{.status.phase}')
img=$(jp get pod ts-static-cp1 -n default -o jsonpath='{.spec.containers[0].image}')
owner=$(jp get pod ts-static-cp1 -n default -o jsonpath='{.metadata.ownerReferences[0].kind}')
if [ "$phase" = "Running" ] && printf '%s' "$img" | grep -q 'nginx:1.29-alpine' && [ "$owner" = "Node" ]; then
  pass 8 "A2 static pod — ts-static-cp1 Running (image corrigée)" $d
else fail 8 "A2 static pod — corriger le manifest statique sur cp1 (pod Running)" $d "phase=${phase:-absent}, image=${img:-∅}, owner=${owner:-?} (attendu Running/nginx:1.29-alpine/Node)"; fi

# A3 — noeud w1 remis en service, billing planifié (8)
d=ARCH
avail=$(jp -n ts-nodes get deploy billing -o jsonpath='{.status.availableReplicas}')
if [ "${avail:-0}" -ge 1 ]; then
  pass 8 "A3 noeud — w1 réparé (cordon + taint), billing disponible" $d
else
  u1=$(jp get node w1 -o jsonpath='{.spec.unschedulable}')
  t1=$(jp get node w1 -o jsonpath='{.spec.taints[?(@.key=="maintenance")].effect}')
  fail 8 "A3 noeud — remettre w1 en service pour que 'billing' démarre" $d "billing available=${avail:-0} ; w1 unschedulable=${u1:-false}, taint maintenance=${t1:-∅}"
fi

# A4 — objet Terminating débloqué (4)
d=ARCH
if jp -n ts-arch get cm stuck-cm >/dev/null 2>&1; then
  dt=$(jp -n ts-arch get cm stuck-cm -o jsonpath='{.metadata.deletionTimestamp}')
  fail 4 "A4 finalizer — la ConfigMap stuck-cm doit être réellement supprimée" $d "stuck-cm encore présente (deletionTimestamp=${dt:-∅} → finalizer non retiré)"
else
  pass 4 "A4 finalizer — stuck-cm débloquée et supprimée" $d
fi

# ══════════════════════════════════════════════════════════════════════════════
dom WORK 32 "📦 Workloads & Scheduling"

# W1 — image réparée (6)
d=WORK
img=$(jp -n ts-work get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
avail=$(jp -n ts-work get deploy web -o jsonpath='{.status.availableReplicas}')
if printf '%s' "$img" | grep -q 'nginx:1.29-alpine' && [ "${avail:-0}" -ge 1 ]; then
  pass 6 "W1 image — deploy web répare et disponible" $d
else fail 6 "W1 image — corriger l'image de 'web' (pods Running)" $d "image=${img:-∅}, availableReplicas=${avail:-0}"; fi

# W2 — CrashLoop réparé (6)
# NB : un pod en CrashLoopBackOff a quand même .status.phase=Running → on note la
# readiness du conteneur (false en CrashLoop, true quand il tourne réellement).
d=WORK
phase=$(jp -n ts-work get pod crasher -o jsonpath='{.status.phase}')
ready=$(jp -n ts-work get pod crasher -o jsonpath='{.status.containerStatuses[0].ready}')
if [ "$phase" = "Running" ] && [ "$ready" = "true" ]; then
  pass 6 "W2 CrashLoop — crasher tourne (conteneur Ready)" $d
else
  rc=$(jp -n ts-work get pod crasher -o jsonpath='{.status.containerStatuses[0].restartCount}')
  reason=$(jp -n ts-work get pod crasher -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}')
  fail 6 "W2 CrashLoop — 'crasher' doit tourner durablement (conteneur Ready)" $d "phase=${phase:-absent}, ready=${ready:-?}, restartCount=${rc:-?}${reason:+, état=$reason}"
fi

# W3 — clé de Secret ajoutée (6)
d=WORK
phase=$(jp -n ts-work get pod checkout -o jsonpath='{.status.phase}')
val=$(jp -n ts-work exec checkout -- printenv DB_PASSWORD 2>/dev/null | tr -d '\r\n')
if [ "$phase" = "Running" ] && [ -n "$val" ]; then
  pass 6 "W3 Secret — checkout Running, DB_PASSWORD injectée" $d
else fail 6 "W3 Secret — ajouter la clé manquante pour que 'checkout' démarre" $d "phase=${phase:-absent}, DB_PASSWORD runtime=${val:-∅}"; fi

# W4 — Pending (requests) réparé (5)
d=WORK
phase=$(jp -n ts-work get pod report -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass 5 "W4 Pending — report est Running" $d
else fail 5 "W4 Pending — 'report' doit tourner (requests réalistes)" $d "phase=${phase:-absent}"; fi

# W5 — Pending (nodeSelector) réparé (5)
d=WORK
phase=$(jp -n ts-work get pod analytics -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass 5 "W5 Pending — analytics est Running" $d
else
  sel=$(jp -n ts-work get pod analytics -o jsonpath='{.spec.nodeSelector.disktype}')
  fail 5 "W5 Pending — 'analytics' doit être planifiable (nodeSelector)" $d "phase=${phase:-absent}, nodeSelector disktype=${sel:-∅} (aucun noeud labelisé ?)"
fi

# W6 — readiness corrigée (4)
d=WORK
rr=$(jp -n ts-work get deploy frontend -o jsonpath='{.status.readyReplicas}')
if [ "${rr:-0}" -ge 1 ]; then
  pass 4 "W6 readiness — frontend a des réplicas Ready" $d
else fail 4 "W6 readiness — corriger la sonde de 'frontend' (readyReplicas ≥ 1)" $d "readyReplicas=${rr:-0}"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom NET 26 "🌐 Services & Networking"

# N1 — endpoints rétablis (7)
d=NET
eps=$(jp -n ts-net get endpoints api-svc -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$eps" -ge 1 ]; then
  pass 7 "N1 endpoints — api-svc a ${eps} endpoint(s)" $d
else fail 7 "N1 endpoints — corriger le selector d'api-svc" $d "api-svc a ${eps} endpoint (attendu ≥ 1)"; fi

# N2 — targetPort corrigé (7, test en direct)
d=NET
if jp -n ts-net exec shop-client -- wget -T 4 -qO- http://shop-svc >/dev/null 2>&1; then
  pass 7 "N2 targetPort — shop-client joint shop-svc" $d
else fail 7 "N2 targetPort — corriger le targetPort de shop-svc (trafic OK)" $d "wget shop-client → shop-svc échoue (targetPort ≠ port du conteneur ?)"; fi

# N3 — NetworkPolicy corrigée (7, test en direct)
d=NET
if jp -n ts-netpol exec client -- wget -T 4 -qO- http://backend >/dev/null 2>&1; then
  pass 7 "N3 NetworkPolicy — client joint backend" $d
else fail 7 "N3 NetworkPolicy — autoriser client → backend (trafic OK)" $d "wget client → backend bloqué (default-deny non corrigé ?)"; fi

# N4 — DNS rétabli (5, test en direct)
d=NET
if jp -n ts-net exec dns-broken -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
  pass 5 "N4 DNS — dns-broken résout les services du cluster" $d
else
  dp=$(jp -n ts-net get pod dns-broken -o jsonpath='{.spec.dnsPolicy}')
  fail 5 "N4 DNS — 'dns-broken' doit résoudre *.svc.cluster.local" $d "dnsPolicy=${dp:-∅} ; résolution kubernetes.default échoue"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 14 "💾 Storage"

# S1 — PVC Bound (7)
d=STO
ph=$(jp -n ts-storage get pvc data -o jsonpath='{.status.phase}')
if [ "$ph" = "Bound" ]; then
  pass 7 "S1 PVC — 'data' est Bound" $d
else
  sc=$(jp -n ts-storage get pvc data -o jsonpath='{.spec.storageClassName}')
  fail 7 "S1 PVC — 'data' doit se lier à un PV (Bound)" $d "phase=${ph:-absent}, storageClassName=${sc:-∅} (aucun PV dans cette classe ?)"
fi

# S2 — Pod monté sur PVC (7)
d=STO
phase=$(jp -n ts-storage get pod app -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass 7 "S2 PVC manquante — 'app' est Running (PVC créée)" $d
else
  claim=$(jp -n ts-storage get pod app -o jsonpath='{.spec.volumes[0].persistentVolumeClaim.claimName}')
  exists=$(jp -n ts-storage get pvc "${claim:-app-pvc}" -o jsonpath='{.status.phase}')
  fail 7 "S2 PVC manquante — créer la PVC référencée par 'app'" $d "phase=${phase:-absent}, PVC '${claim:-app-pvc}'=${exists:-absente}"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "────────────────────────────────────────────────────────"
printf "\033[1mSous-totaux par domaine :\033[0m\n"
order=(ARCH WORK NET STO)
names=( "Cluster Architecture & Nodes" "Workloads & Scheduling" "Services & Networking" "Storage" )
for i in "${!order[@]}"; do
  k=${order[$i]}
  printf "  %-32s %2d / %2d\n" "${names[$i]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
done
echo "────────────────────────────────────────────────────────"
printf "\033[1mSCORE TOTAL : %d / 100\033[0m\n" "$SCORE"
if [ "$SCORE" -ge 75 ]; then
  printf "\033[32m🎉 OBJECTIF ATTEINT (≥ 75%%)\033[0m\n"
else
  printf "\033[31mÀ RETRAVAILLER (< 75%%) — il manque %d pts\033[0m\n" $((75-SCORE))
fi
echo "────────────────────────────────────────────────────────"
