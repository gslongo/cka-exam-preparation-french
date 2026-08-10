#!/usr/bin/env bash
# grade.sh — correction automatique de l'examen blanc CKA.
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-01/grade.sh"
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

# T1 — RBAC (7)
d=ARCH
can_list=$(jp auth can-i list pods --as=system:serviceaccount:rbac-test:deploy-bot -n rbac-test)
can_del=$(jp auth can-i delete pods --as=system:serviceaccount:rbac-test:deploy-bot -n rbac-test)
if jp -n rbac-test get sa deploy-bot >/dev/null \
   && jp -n rbac-test get role pod-reader >/dev/null \
   && jp -n rbac-test get rolebinding deploy-bot-read >/dev/null \
   && [ "$can_list" = "yes" ] && [ "$can_del" = "no" ]; then
  pass 7 "T1 RBAC — deploy-bot peut lister mais pas supprimer les pods" $d
else
  r=""
  jp -n rbac-test get sa deploy-bot >/dev/null              || r+="SA deploy-bot absent; "
  jp -n rbac-test get role pod-reader >/dev/null            || r+="Role pod-reader absent; "
  jp -n rbac-test get rolebinding deploy-bot-read >/dev/null || r+="RoleBinding deploy-bot-read absent; "
  [ "$can_list" = "yes" ] || r+="ne peut pas 'list' les pods; "
  [ "$can_del" = "no" ]   || r+="peut 'delete' les pods (droits trop larges); "
  fail 7 "T1 RBAC — SA/Role/RoleBinding + permissions exactes" $d "${r%; }"
fi

# T2 — etcd snapshot (8)
d=ARCH
if sudo test -s /opt/etcd-backup.db 2>/dev/null; then
  ok=0
  if command -v etcdutl >/dev/null 2>&1; then sudo etcdutl snapshot status /opt/etcd-backup.db >/dev/null 2>&1 && ok=1
  elif command -v etcdctl >/dev/null 2>&1; then sudo ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db >/dev/null 2>&1 && ok=1
  else ok=1; fi   # pas d'outil de validation dispo → on se contente d'un fichier non vide
  sz=$(sudo stat -c%s /opt/etcd-backup.db 2>/dev/null || echo 0)
  if [ "$ok" = "1" ] && [ "$sz" -gt 1024 ]; then pass 8 "T2 etcd — snapshot /opt/etcd-backup.db valide" $d
  else fail 8 "T2 etcd — snapshot présent mais invalide/trop petit" $d "taille=${sz} o, statut snapshot=$([ "$ok" = 1 ] && echo ok || echo invalide)"; fi
else fail 8 "T2 etcd — /opt/etcd-backup.db absent ou vide" $d "fichier /opt/etcd-backup.db absent ou vide"; fi

# T3 — static pod sur w1 (5)
d=ARCH
phase=$(jp get pod static-web-w1 -n default -o jsonpath='{.status.phase}')
node=$(jp get pod static-web-w1 -n default -o jsonpath='{.spec.nodeName}')
owner=$(jp get pod static-web-w1 -n default -o jsonpath='{.metadata.ownerReferences[0].kind}')
if [ "$phase" = "Running" ] && [ "$node" = "w1" ] && [ "$owner" = "Node" ]; then
  pass 5 "T3 static pod — static-web-w1 Running sur w1" $d
else fail 5 "T3 static pod — static-web-w1 Running sur w1 (via manifests statiques)" $d "phase=${phase:-absent}, node=${node:-?}, owner=${owner:-?} (attendu Running/w1/Node)"; fi

# T4 — w2 unschedulable (5)
d=ARCH
u2=$(jp get node w2 -o jsonpath='{.spec.unschedulable}')
if [ "$u2" = "true" ]; then
  pass 5 "T4 maintenance — w2 SchedulingDisabled" $d
else fail 5 "T4 maintenance — w2 doit être cordonné (SchedulingDisabled)" $d "w2 unschedulable=${u2:-false} (attendu true)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom WORK 15 "📦 Workloads & Scheduling"

# T5 — deployment web (5)
d=WORK
img=$(jp -n workloads get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
rr=$(jp -n workloads get deploy web -o jsonpath='{.status.readyReplicas}')
if [ "$rr" = "3" ] && printf '%s' "$img" | grep -q 'nginx:1.29-alpine'; then
  pass 5 "T5 Deployment web — 3/3 Ready, image OK" $d
else fail 5 "T5 Deployment web — 3 réplicas nginx:1.29-alpine" $d "readyReplicas=${rr:-0}, image=${img:-∅}"; fi

# T6 — configmap -> env (5)
d=WORK
cmval=$(jp -n workloads get cm app-config -o jsonpath='{.data.APP_COLOR}')
phase=$(jp -n workloads get pod color-pod -o jsonpath='{.status.phase}')
# On accepte les 3 formes valides : env.valueFrom.configMapKeyRef, envFrom.configMapRef,
# ou la preuve runtime (APP_COLOR=blue réellement présent dans l'environnement du conteneur).
envref=$(jp -n workloads get pod color-pod -o jsonpath='{.spec.containers[0].env[?(@.name=="APP_COLOR")].valueFrom.configMapKeyRef.name}')
envfrom=$(jp -n workloads get pod color-pod -o jsonpath='{.spec.containers[0].envFrom[?(@.configMapRef.name=="app-config")].configMapRef.name}')
envval=$(jp -n workloads exec color-pod -- printenv APP_COLOR 2>/dev/null | tr -d '\r\n')
if [ "$cmval" = "blue" ] && [ "$phase" = "Running" ] \
   && { [ "$envref" = "app-config" ] || [ "$envfrom" = "app-config" ] || [ "$envval" = "blue" ]; }; then
  pass 5 "T6 ConfigMap→env — APP_COLOR injectée depuis app-config" $d
else fail 5 "T6 ConfigMap→env — CM app-config(APP_COLOR=blue) + color-pod avec env depuis la CM" $d "cm APP_COLOR=${cmval:-∅}, color-pod phase=${phase:-absent}, env from CM=${envref:-${envfrom:-∅}}, APP_COLOR runtime=${envval:-∅}"; fi

# T7 — nodeSelector sur w1 (5)
d=WORK
lbl=$(jp get node w1 -o jsonpath='{.metadata.labels.disktype}')
sel=$(jp -n workloads get pod ssd-pod -o jsonpath='{.spec.nodeSelector.disktype}')
node=$(jp -n workloads get pod ssd-pod -o jsonpath='{.spec.nodeName}')
phase=$(jp -n workloads get pod ssd-pod -o jsonpath='{.status.phase}')
if [ "$lbl" = "ssd" ] && [ "$sel" = "ssd" ] && [ "$node" = "w1" ] && [ "$phase" = "Running" ]; then
  pass 5 "T7 nodeSelector — ssd-pod Running sur w1 (disktype=ssd)" $d
else fail 5 "T7 nodeSelector — label w1 disktype=ssd + ssd-pod planifié dessus" $d "w1 disktype=${lbl:-∅}, ssd-pod nodeSelector=${sel:-∅}, node=${node:-?}, phase=${phase:-absent}"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom NET 20 "🌐 Services & Networking"

# T8 — ClusterIP web-svc (5)
d=NET
typ=$(jp -n workloads get svc web-svc -o jsonpath='{.spec.type}')
eps=$(jp -n workloads get endpoints web-svc -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$typ" = "ClusterIP" ] && [ "$eps" -ge 3 ]; then
  pass 5 "T8 ClusterIP — web-svc, ${eps} endpoints" $d
else fail 5 "T8 ClusterIP — web-svc ClusterIP avec 3 endpoints" $d "type=${typ:-absent}, endpoints=${eps} (attendu ClusterIP/≥3)"; fi

# T9 — NodePort web-np (5)
d=NET
typ=$(jp -n workloads get svc web-np -o jsonpath='{.spec.type}')
np=$(jp -n workloads get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
eps=$(jp -n workloads get endpoints web-np -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$typ" = "NodePort" ] && [ "$np" = "30080" ] && [ "$eps" -ge 1 ]; then
  pass 5 "T9 NodePort — web-np nodePort 30080, ${eps} endpoints" $d
else fail 5 "T9 NodePort — web-np NodePort 30080 avec endpoints" $d "type=${typ:-absent}, nodePort=${np:-∅}, endpoints=${eps} (attendu NodePort/30080/≥1)"; fi

# T10 — NetworkPolicy (10 : 6 spec + 4 enforcement)
d=NET
np_pod=$(jp -n netpol get netpol backend-allow-frontend -o jsonpath='{.spec.podSelector.matchLabels.app}')
np_from=$(jp -n netpol get netpol backend-allow-frontend -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels.app}')
np_port=$(jp -n netpol get netpol backend-allow-frontend -o jsonpath='{.spec.ingress[0].ports[0].port}')
if [ "$np_pod" = "backend" ] && [ "$np_from" = "frontend" ] && [ "$np_port" = "80" ]; then
  pass 6 "T10a NetworkPolicy — spec correcte (backend ← frontend :80)" $d
else fail 6 "T10a NetworkPolicy — podSelector app=backend, from app=frontend, port 80" $d "podSelector=${np_pod:-∅}, from=${np_from:-∅}, port=${np_port:-∅}"; fi
# enforcement : frontend OK, client bloqué
fe=1; cl=1
jp -n netpol exec frontend -- wget -T 3 -qO- http://backend >/dev/null 2>&1 || fe=0
jp -n netpol exec client   -- wget -T 3 -qO- http://backend >/dev/null 2>&1 && cl=0
if [ "$fe" = "1" ] && [ "$cl" = "1" ]; then
  pass 4 "T10b NetworkPolicy — frontend joint backend, client bloqué" $d
else fail 4 "T10b NetworkPolicy — enforcement (frontend OK / client bloqué)" $d "frontend→backend=$([ "$fe" = 1 ] && echo OK || echo bloqué), client→backend=$([ "$cl" = 1 ] && echo bloqué || echo passe)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 10 "💾 Storage"

# T11 — PV + PVC bound (6)
d=STO
pvcphase=$(jp -n storage get pvc pvc-manual -o jsonpath='{.status.phase}')
boundto=$(jp -n storage get pvc pvc-manual -o jsonpath='{.spec.volumeName}')
if [ "$pvcphase" = "Bound" ] && [ "$boundto" = "pv-manual" ]; then
  pass 6 "T11 PV/PVC — pvc-manual Bound à pv-manual" $d
else fail 6 "T11 PV/PVC — pvc-manual doit être Bound à pv-manual" $d "pvc phase=${pvcphase:-absent}, liée à=${boundto:-∅} (attendu Bound/pv-manual)"; fi

# T12 — pod monté sur PVC (4)
d=STO
phase=$(jp -n storage get pod pv-pod -o jsonpath='{.status.phase}')
claim=$(jp -n storage get pod pv-pod -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}')
mp=$(jp -n storage get pod pv-pod -o jsonpath='{.spec.containers[0].volumeMounts[?(@.mountPath=="/usr/share/nginx/html")].name}')
if [ "$phase" = "Running" ] && [ "$claim" = "pvc-manual" ] && [ -n "$mp" ]; then
  pass 4 "T12 Pod PVC — pv-pod Running, pvc-manual monté au bon chemin" $d
else fail 4 "T12 Pod PVC — pv-pod monte pvc-manual sur /usr/share/nginx/html" $d "phase=${phase:-absent}, claim=${claim:-∅}, montage /usr/share/nginx/html=$([ -n "$mp" ] && echo oui || echo non)"; fi

# ══════════════════════════════════════════════════════════════════════════════
dom TS 30 "🔧 Troubleshooting"

# T13 — image réparée (6)
d=TS
img=$(jp -n trouble get deploy tshoot-web -o jsonpath='{.spec.template.spec.containers[0].image}')
avail=$(jp -n trouble get deploy tshoot-web -o jsonpath='{.status.availableReplicas}')
if printf '%s' "$img" | grep -q 'nginx:1.29-alpine' && [ "${avail:-0}" -ge 1 ]; then
  pass 6 "T13 image — tshoot-web répare et disponible" $d
else fail 6 "T13 image — corriger l'image de tshoot-web (pods Running)" $d "image actuelle=${img:-∅}, availableReplicas=${avail:-0}"; fi

# T14 — endpoints service (8)
d=TS
eps=$(jp -n trouble get endpoints api-svc -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$eps" -ge 1 ]; then
  pass 8 "T14 endpoints — api-svc a ${eps} endpoint(s)" $d
else fail 8 "T14 endpoints — corriger le selector d'api-svc" $d "api-svc a ${eps} endpoint (attendu ≥1)"; fi

# T15 — pod hungry Running (8)
d=TS
phase=$(jp -n trouble get pod hungry -o jsonpath='{.status.phase}')
img=$(jp -n trouble get pod hungry -o jsonpath='{.spec.containers[0].image}')
if [ "$phase" = "Running" ] && printf '%s' "$img" | grep -q 'nginx:1.29-alpine'; then
  pass 8 "T15 Pending — hungry est Running" $d
else fail 8 "T15 Pending — hungry doit tourner (recréer avec des requests réalistes)" $d "phase=${phase:-absent}, image=${img:-∅}"; fi

# T16 — configmap créée + pods up (8)
d=TS
key=$(jp -n trouble get cm cfg-app-config -o jsonpath='{.data.app\.properties}')
avail=$(jp -n trouble get deploy cfg-app -o jsonpath='{.status.availableReplicas}')
if [ -n "$key" ] && [ "${avail:-0}" -ge 1 ]; then
  pass 8 "T16 ConfigMap manquante — cfg-app-config créée, cfg-app Running" $d
else fail 8 "T16 ConfigMap manquante — créer cfg-app-config(app.properties) + pods Running" $d "cm app.properties=$([ -n "$key" ] && echo présente || echo absente), availableReplicas=${avail:-0}"; fi

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
