#!/usr/bin/env bash
# grade.sh — correction automatique de l'examen blanc CKA n°2 (niveau avancé).
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-02/grade.sh"
#
# N'effectue AUCUNE modification : lecture seule. Affiche PASS/FAIL par tâche
# (avec le symptôme observé en cas d'échec, mais JAMAIS la solution),
# sous-total par domaine et score /100 (réussite ≥ 66).
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }

# jsonpath helper (silencieux)
jp() { kubectl "$@" 2>/dev/null; }

# ══════════════════════════════════════════════════════════════════════════════
dom ARCH 25 "🏛️  Cluster Architecture"

# T1 — RBAC cluster-scoped (7)
d=ARCH
can_create=$(jp auth can-i create deployments --as=system:serviceaccount:platform:ci-bot -n default)
can_delnode=$(jp auth can-i delete nodes --as=system:serviceaccount:platform:ci-bot)
if jp -n platform get sa ci-bot >/dev/null \
   && jp get clusterrole deploy-admin >/dev/null \
   && jp get clusterrolebinding ci-bot-deploy >/dev/null \
   && [ "$can_create" = "yes" ] && [ "$can_delnode" = "no" ]; then
  pass 7 "T1 RBAC — ci-bot gère les Deployments partout, sans toucher aux nodes" $d
else
  r=""
  jp -n platform get sa ci-bot >/dev/null            || r+="SA platform/ci-bot absent; "
  jp get clusterrole deploy-admin >/dev/null         || r+="ClusterRole deploy-admin absent; "
  jp get clusterrolebinding ci-bot-deploy >/dev/null || r+="ClusterRoleBinding ci-bot-deploy absent; "
  [ "$can_create" = "yes" ] || r+="ci-bot ne peut pas créer de Deployment; "
  [ "$can_delnode" = "no" ] || r+="ci-bot peut supprimer des nodes (droits trop larges); "
  fail 7 "T1 RBAC — SA + ClusterRole + ClusterRoleBinding (deployments cluster-wide)" $d "${r%; }"
fi

# T2 — upgrade control plane cp1 vers 1.35 (8) — TÂCHE FINALE (irréversible)
d=ARCH
cpver=$(jp get node cp1 -o jsonpath='{.status.nodeInfo.kubeletVersion}')
if printf '%s' "$cpver" | grep -q '^v1\.35\.'; then
  pass 8 "T2 upgrade — cp1 migré en $cpver (control plane en 1.35)" $d
else fail 8 "T2 upgrade — passer le control plane cp1 de 1.34 à 1.35 (kubeadm upgrade)" $d "cp1 kubelet=${cpver:-?} (attendu v1.35.x)"; fi

# T3 — static pod sur w1 avec label (5)
d=ARCH
phase=$(jp get pod static-web-w1 -n default -o jsonpath='{.status.phase}')
node=$(jp get pod static-web-w1 -n default -o jsonpath='{.spec.nodeName}')
owner=$(jp get pod static-web-w1 -n default -o jsonpath='{.metadata.ownerReferences[0].kind}')
role=$(jp get pod static-web-w1 -n default -o jsonpath='{.metadata.labels.role}')
if [ "$phase" = "Running" ] && [ "$node" = "w1" ] && [ "$owner" = "Node" ] && [ "$role" = "cache" ]; then
  pass 5 "T3 static pod — static-web-w1 Running sur w1 (label role=cache)" $d
else fail 5 "T3 static pod — static-web (label role=cache) via les manifests statiques de w1" $d "phase=${phase:-absent}, node=${node:-?}, owner=${owner:-?}, label role=${role:-∅} (attendu Running/w1/Node/cache)"; fi

# T4 — scheduling manuel sur w2 (5)
d=ARCH
node=$(jp -n apps get pod pinned -o jsonpath='{.spec.nodeName}')
phase=$(jp -n apps get pod pinned -o jsonpath='{.status.phase}')
if [ "$node" = "w2" ] && [ "$phase" = "Running" ]; then
  pass 5 "T4 scheduling manuel — pinned épinglé sur w2" $d
else fail 5 "T4 scheduling manuel — pod pinned placé sur w2 sans le scheduler (nodeName)" $d "node=${node:-?}, phase=${phase:-absent} (attendu w2/Running)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom WORK 15 "📦 Workloads & Scheduling"

# T5 — deployment api + stratégie (5)
d=WORK
img=$(jp -n apps get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}')
rr=$(jp -n apps get deploy api -o jsonpath='{.status.readyReplicas}')
mu=$(jp -n apps get deploy api -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}')
if [ "${rr:-0}" = "3" ] && printf '%s' "$img" | grep -q 'nginx:1.29-alpine' && [ "$mu" = "0" ]; then
  pass 5 "T5 Deployment api — 3/3 Ready, maxUnavailable=0" $d
else fail 5 "T5 Deployment api — 3 réplicas nginx:1.29-alpine, RollingUpdate maxUnavailable=0" $d "readyReplicas=${rr:-0}, image=${img:-∅}, maxUnavailable=${mu:-∅} (attendu 3/nginx:1.29-alpine/0)"; fi

# T6 — secret -> env (5)
d=WORK
skey=$(jp -n apps get secret app-secret -o jsonpath='{.data.TOKEN}')
phase=$(jp -n apps get pod secret-pod -o jsonpath='{.status.phase}')
# On accepte les 3 formes valides : env.valueFrom.secretKeyRef, envFrom.secretRef,
# ou la preuve runtime (variable TOKEN réellement présente dans l'environnement du conteneur).
ref=$(jp -n apps get pod secret-pod -o jsonpath='{.spec.containers[0].env[?(@.name=="TOKEN")].valueFrom.secretKeyRef.name}')
reffrom=$(jp -n apps get pod secret-pod -o jsonpath='{.spec.containers[0].envFrom[?(@.secretRef.name=="app-secret")].secretRef.name}')
refval=$(jp -n apps exec secret-pod -- printenv TOKEN 2>/dev/null | tr -d '\r\n')
if [ -n "$skey" ] && [ "$phase" = "Running" ] \
   && { [ "$ref" = "app-secret" ] || [ "$reffrom" = "app-secret" ] || [ -n "$refval" ]; }; then
  pass 5 "T6 Secret→env — TOKEN injecté depuis app-secret" $d
else fail 5 "T6 Secret→env — Secret app-secret(TOKEN) + secret-pod avec env depuis le Secret" $d "secret TOKEN=$([ -n "$skey" ] && echo présent || echo absent), pod phase=${phase:-absent}, env from secret=${ref:-${reffrom:-∅}}, TOKEN runtime=$([ -n "$refval" ] && echo présent || echo ∅)"; fi

# T7 — taint + toleration (5)
d=WORK
taint=$(jp get node w1 -o jsonpath='{.spec.taints[?(@.key=="dedicated")].value}')
node=$(jp -n apps get pod tolerant -o jsonpath='{.spec.nodeName}')
phase=$(jp -n apps get pod tolerant -o jsonpath='{.status.phase}')
tol=$(jp -n apps get pod tolerant -o jsonpath='{.spec.tolerations[?(@.key=="dedicated")].key}')
if [ "$taint" = "cka" ] && [ "$node" = "w1" ] && [ "$phase" = "Running" ] && [ "$tol" = "dedicated" ]; then
  pass 5 "T7 taint/toleration — w1 taintée, tolerant planifié dessus" $d
else fail 5 "T7 taint/toleration — taint dedicated=cka:NoSchedule sur w1 + pod tolerant dessus" $d "w1 taint dedicated=${taint:-∅}, pod node=${node:-?}, phase=${phase:-absent}, toleration dedicated=$([ -n "$tol" ] && echo oui || echo non)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom NET 20 "🌐 Services & Networking"

# T8 — Ingress api-ing (5) — pas de contrôleur dans le lab : on note la définition
d=NET
ihost=$(jp -n apps get ingress api-ing -o jsonpath='{.spec.rules[0].host}')
isvc=$(jp -n apps get ingress api-ing -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
iport=$(jp -n apps get ingress api-ing -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}')
ipath=$(jp -n apps get ingress api-ing -o jsonpath='{.spec.rules[0].http.paths[0].path}')
if [ "$ihost" = "api.cka.local" ] && [ "$isvc" = "api-np" ] && [ "$iport" = "80" ] && [ -n "$ipath" ]; then
  pass 5 "T8 Ingress — api-ing : api.cka.local → api-np:80" $d
else fail 5 "T8 Ingress — api-ing (host api.cka.local, path /, backend api-np:80)" $d "host=${ihost:-∅}, backend=${isvc:-∅}:${iport:-∅}, path=${ipath:-∅} (attendu api.cka.local/api-np/80/'/')"; fi

# T9 — NodePort api-np (5)
d=NET
typ=$(jp -n apps get svc api-np -o jsonpath='{.spec.type}')
np=$(jp -n apps get svc api-np -o jsonpath='{.spec.ports[0].nodePort}')
eps=$(jp -n apps get endpoints api-np -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$typ" = "NodePort" ] && [ "$np" = "30090" ] && [ "$eps" -ge 1 ]; then
  pass 5 "T9 NodePort — api-np nodePort 30090, ${eps} endpoints" $d
else fail 5 "T9 NodePort — api-np NodePort 30090 avec endpoints" $d "type=${typ:-absent}, nodePort=${np:-∅}, endpoints=${eps} (attendu NodePort/30090/≥1)"; fi

# T10 — NetworkPolicy default-deny + allow (10 : 6 spec + 4 enforcement)
d=NET
dd=$(jp -n secure get netpol default-deny-ingress -o jsonpath='{.spec.policyTypes[*]}')
allow_pod=$(jp -n secure get netpol allow-web-to-db -o jsonpath='{.spec.podSelector.matchLabels.app}')
allow_from=$(jp -n secure get netpol allow-web-to-db -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels.app}')
allow_port=$(jp -n secure get netpol allow-web-to-db -o jsonpath='{.spec.ingress[0].ports[0].port}')
if printf '%s' "$dd" | grep -qw Ingress && [ "$allow_pod" = "db" ] && [ "$allow_from" = "web" ] && [ "$allow_port" = "80" ]; then
  pass 6 "T10a NetworkPolicy — default-deny + allow web→db:80" $d
else
  r=""
  printf '%s' "$dd" | grep -qw Ingress  || r+="default-deny-ingress absente/incorrecte; "
  [ "$allow_pod" = "db" ]   || r+="allow: podSelector≠app=db; "
  [ "$allow_from" = "web" ] || r+="allow: from≠app=web; "
  [ "$allow_port" = "80" ]  || r+="allow: port≠80; "
  fail 6 "T10a NetworkPolicy — default-deny-ingress + allow-web-to-db (app=db ← app=web :80)" $d "${r%; }"
fi
# enforcement : web OK, scanner bloqué
web=1; scan=1
jp -n secure exec web     -- wget -T 3 -qO- http://db >/dev/null 2>&1 || web=0
jp -n secure exec scanner -- wget -T 3 -qO- http://db >/dev/null 2>&1 && scan=0
if [ "$web" = "1" ] && [ "$scan" = "1" ]; then
  pass 4 "T10b NetworkPolicy — web joint db, scanner bloqué" $d
else fail 4 "T10b NetworkPolicy — enforcement (web OK / scanner bloqué)" $d "web→db=$([ "$web" = 1 ] && echo OK || echo bloqué), scanner→db=$([ "$scan" = 1 ] && echo bloqué || echo passe)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 10 "💾 Storage"

# T11 — PV (Retain) + PVC bound (6)
d=STO
pvcphase=$(jp -n storage get pvc data -o jsonpath='{.status.phase}')
boundto=$(jp -n storage get pvc data -o jsonpath='{.spec.volumeName}')
reclaim=$(jp get pv pv-fast -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
if [ "$pvcphase" = "Bound" ] && [ "$boundto" = "pv-fast" ] && [ "$reclaim" = "Retain" ]; then
  pass 6 "T11 PV/PVC — data Bound à pv-fast (Retain)" $d
else fail 6 "T11 PV/PVC — pv-fast (Retain) lié à la PVC data" $d "pvc phase=${pvcphase:-absent}, liée à=${boundto:-∅}, reclaimPolicy=${reclaim:-∅} (attendu Bound/pv-fast/Retain)"; fi

# T12 — pod monté via subPath (4)
d=STO
phase=$(jp -n storage get pod app -o jsonpath='{.status.phase}')
claim=$(jp -n storage get pod app -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}')
mp=$(jp -n storage get pod app -o jsonpath='{.spec.containers[0].volumeMounts[?(@.mountPath=="/usr/share/nginx/html")].name}')
sub=$(jp -n storage get pod app -o jsonpath='{.spec.containers[0].volumeMounts[?(@.mountPath=="/usr/share/nginx/html")].subPath}')
if [ "$phase" = "Running" ] && [ "$claim" = "data" ] && [ -n "$mp" ] && [ "$sub" = "html" ]; then
  pass 4 "T12 Pod subPath — app monte data (subPath html) au bon chemin" $d
else fail 4 "T12 Pod subPath — app monte la PVC data sur /usr/share/nginx/html (subPath html)" $d "phase=${phase:-absent}, claim=${claim:-∅}, montage=$([ -n "$mp" ] && echo oui || echo non), subPath=${sub:-∅} (attendu Running/data/oui/html)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom TS 30 "🔧 Troubleshooting"

# T13 — readinessProbe cassée (6)
d=TS
avail=$(jp -n trouble get deploy frontend -o jsonpath='{.status.availableReplicas}')
if [ "${avail:-0}" -ge 1 ]; then
  pass 6 "T13 readinessProbe — frontend disponible" $d
else fail 6 "T13 readinessProbe — corriger la sonde de frontend (pods Ready)" $d "availableReplicas=${avail:-0} (attendu ≥1)"; fi

# T14 — résolution DNS (8)
d=TS
phase=$(jp -n trouble get pod dns-check -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ] && timeout 20 kubectl -n trouble exec dns-check -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
  pass 8 "T14 DNS — dns-check résout les noms du cluster" $d
else fail 8 "T14 DNS — réparer la config DNS de dns-check (résolution des services cluster)" $d "phase=${phase:-absent}, résolution kubernetes.default.svc.cluster.local=$(timeout 20 kubectl -n trouble exec dns-check -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 && echo OK || echo KO)"; fi

# T15 — pod stuck Running (8)
d=TS
phase=$(jp -n trouble get pod stuck -o jsonpath='{.status.phase}')
img=$(jp -n trouble get pod stuck -o jsonpath='{.spec.containers[0].image}')
if [ "$phase" = "Running" ] && printf '%s' "$img" | grep -q 'nginx:1.29-alpine'; then
  pass 8 "T15 Pending — stuck est Running" $d
else fail 8 "T15 Pending — stuck doit tourner (contrainte de placement impossible → recréer)" $d "phase=${phase:-absent}, image=${img:-∅}"; fi

# T16 — secret manquant créé + pods up (8)
d=TS
key=$(jp -n trouble get secret billing-secret -o jsonpath='{.data.API_KEY}')
avail=$(jp -n trouble get deploy billing -o jsonpath='{.status.availableReplicas}')
if [ -n "$key" ] && [ "${avail:-0}" -ge 1 ]; then
  pass 8 "T16 Secret manquant — billing-secret créé, billing Running" $d
else fail 8 "T16 Secret manquant — créer billing-secret(API_KEY) + pods Running" $d "secret API_KEY=$([ -n "$key" ] && echo présente || echo absente), availableReplicas=${avail:-0}"; fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "────────────────────────────────────────────────────────"
printf "\033[1mSous-totaux par domaine :\033[0m\n"
order=(ARCH WORK NET STO TS)
names=( "Cluster Architecture" "Workloads & Scheduling" "Services & Networking" "Storage" "Troubleshooting" )
for i in "${!order[@]}"; do
  k=${order[$i]}
  printf "  %-26s %2d / %2d\n" "${names[$i]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
done
echo "────────────────────────────────────────────────────────"
printf "\033[1mSCORE TOTAL : %d / 100\033[0m\n" "$SCORE"
if [ "$SCORE" -ge 66 ]; then
  printf "\033[32m🎉 RÉUSSI (≥ 66)\033[0m\n"
else
  printf "\033[31m❌ ÉCHEC (< 66) — il manque %d pts\033[0m\n" $((66-SCORE))
fi
echo "────────────────────────────────────────────────────────"
