#!/usr/bin/env bash
# grade.sh — correction automatique de l'examen blanc CKA n°3 (drills ciblés).
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/grade.sh"
#
# N'effectue AUCUNE modification : lecture seule. Affiche PASS/FAIL par tâche
# (avec le symptôme observé en cas d'échec, mais JAMAIS la solution),
# sous-total par domaine et score total. Réussite ≥ 66 %.
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }

BASE=/opt/exam-03

# ══════════════════════════════════════════════════════════════════════════════
dom KUBECFG 7 "🏛️  Cluster Architecture & kubeconfig"

# T1 — extraction kubeconfig (3 + 2 + 2)
d=KUBECFG
KC="$BASE/kubeconfig"
OUT_CTX="$BASE/contexts"
OUT_CUR="$BASE/current-context"
OUT_CERT="$BASE/cert"

# Vérité terrain calculée depuis le kubeconfig fourni (source unique)
exp_ctx=$(kubectl config --kubeconfig="$KC" get-contexts -o name 2>/dev/null | sort)
exp_cur=$(kubectl config --kubeconfig="$KC" view -o jsonpath='{.current-context}' 2>/dev/null)
exp_cert=$(kubectl config --kubeconfig="$KC" view --raw \
           -o jsonpath="{.users[?(@.name=='audit-user')].user.client-certificate-data}" 2>/dev/null | base64 -d 2>/dev/null)

# 1) contextes (ordre indifférent)
got_ctx=$(sort "$OUT_CTX" 2>/dev/null | sed '/^[[:space:]]*$/d')
if [ -f "$OUT_CTX" ] && [ -n "$exp_ctx" ] && [ "$got_ctx" = "$exp_ctx" ]; then
  pass 3 "T1a contextes — les 3 noms de contextes sont listés" $d
else
  fail 3 "T1a contextes — écrire tous les noms de contextes (un/ligne)" $d \
    "$( [ -f "$OUT_CTX" ] && echo "contenu != attendu (3 contextes)" || echo "$OUT_CTX absent" )"
fi

# 2) current-context
got_cur=$( [ -f "$OUT_CUR" ] && tr -d '[:space:]' < "$OUT_CUR" 2>/dev/null )
if [ -f "$OUT_CUR" ] && [ -n "$exp_cur" ] && [ "$got_cur" = "$exp_cur" ]; then
  pass 2 "T1b current-context — contexte courant correct" $d
else
  fail 2 "T1b current-context — écrire le nom du contexte courant" $d \
    "$( [ -f "$OUT_CUR" ] && echo "attendu '$exp_cur', trouvé '${got_cur:-vide}'" || echo "$OUT_CUR absent" )"
fi

# 3) certificat décodé (base64 -d)
got_cert=$(cat "$OUT_CERT" 2>/dev/null)
# comparaison en ignorant un éventuel saut de ligne final
if [ -f "$OUT_CERT" ] && [ -n "$exp_cert" ] \
   && [ "$(printf '%s' "$got_cert")" = "$(printf '%s' "$exp_cert")" ]; then
  pass 2 "T1c cert — client-certificate de audit-user décodé (base64 -d)" $d
else
  fail 2 "T1c cert — décoder le client-certificate de audit-user" $d \
    "$( [ -f "$OUT_CERT" ] && echo "contenu != certificat décodé attendu" || echo "$OUT_CERT absent" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom PKG 8 "📦 Packaging & Helm"

# T2 — Helm cert-manager + ClusterIssuer (5 + 3)
d=PKG
rel=$(helm list -n pki -q 2>/dev/null | grep -x certman)
crd_ok=$(kubectl get crd clusterissuers.cert-manager.io -o name 2>/dev/null)
if [ -n "$rel" ] && [ -n "$crd_ok" ]; then
  pass 5 "T2a Helm — release certman installée dans pki (CRDs cert-manager présents)" $d
else
  r=""
  [ -n "$rel" ]    || r+="release helm 'certman' absente du ns pki; "
  [ -n "$crd_ok" ] || r+="CRD clusterissuers.cert-manager.io absent; "
  fail 5 "T2a Helm — installer jetstack/cert-manager (release certman, ns pki, crds.enabled)" $d "${r%; }"
fi

ci=$(kubectl get clusterissuer selfsigned-issuer -o name 2>/dev/null)
crl=$(kubectl get clusterissuer selfsigned-issuer -o jsonpath='{.spec.selfSigned.crlDistributionPoints[0]}' 2>/dev/null)
if [ -n "$ci" ] && [ "$crl" = "http://pki.cka.local/crl" ]; then
  pass 3 "T2b ClusterIssuer — selfsigned-issuer créé avec crlDistributionPoints" $d
else
  r=""
  [ -n "$ci" ]                              || r+="ClusterIssuer selfsigned-issuer absent; "
  [ "$crl" = "http://pki.cka.local/crl" ]   || r+="crlDistributionPoints manquant/incorrect; "
  fail 3 "T2b ClusterIssuer — créer selfsigned-issuer (+ crlDistributionPoints)" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom WL 11 "🧱 Workloads & Scheduling"

# T3 — Scaler un StatefulSet à 1 replica (5)
d=WL
sts_rep=$(kubectl -n project-store get statefulset store-db -o jsonpath='{.spec.replicas}' 2>/dev/null)
sts_ready=$(kubectl -n project-store get statefulset store-db -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$sts_rep" = "1" ] && [ "$sts_ready" = "1" ]; then
  pass 5 "T3 StatefulSet — store-db scalé à 1 replica (Pod prêt)" $d
else
  r=""
  [ "$sts_rep" = "1" ]   || r+="spec.replicas=${sts_rep:-absent} (attendu 1); "
  [ "$sts_ready" = "1" ] || r+="readyReplicas=${sts_ready:-0} (attendu 1); "
  fail 5 "T3 StatefulSet — scaler store-db à 1 replica (ns project-store)" $d "${r%; }"
fi

# T4 — QoS : Pods évincés en premier = BestEffort (6)
OUT_QOS="$BASE/qos-evicted-first.txt"
exp_qos=$(kubectl -n project-qos get pods \
            -o jsonpath='{range .items[?(@.status.qosClass=="BestEffort")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
            | sed '/^[[:space:]]*$/d' | sort)
got_qos=$( [ -f "$OUT_QOS" ] && sort "$OUT_QOS" 2>/dev/null | sed '/^[[:space:]]*$/d' )
if [ -f "$OUT_QOS" ] && [ -n "$exp_qos" ] && [ "$got_qos" = "$exp_qos" ]; then
  pass 6 "T4 QoS — Pods BestEffort (évincés en premier) correctement listés" $d
else
  fail 6 "T4 QoS — lister les Pods évincés en premier dans qos-evicted-first.txt" $d \
    "$( [ -f "$OUT_QOS" ] && echo "contenu != liste BestEffort attendue" || echo "$OUT_QOS absent" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom AUTO 12 "🧩 HPA & Kustomize"

# T5 — HPA via Kustomize : staging (4) + prod (4) + ConfigMap supprimée (4)
d=AUTO
s_min=$(kubectl -n api-gw-staging get hpa api-gw -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
s_max=$(kubectl -n api-gw-staging get hpa api-gw -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)
s_cpu=$(kubectl -n api-gw-staging get hpa api-gw -o jsonpath='{.spec.metrics[?(@.type=="Resource")].resource.target.averageUtilization}' 2>/dev/null)
if [ "$s_min" = "2" ] && [ "$s_max" = "4" ] && [ "$s_cpu" = "50" ]; then
  pass 4 "T5a staging — HPA api-gw min2 / max4 / cible CPU 50%" $d
else
  r=""
  [ "$s_min" = "2" ]  || r+="minReplicas=${s_min:-absent}(≠2); "
  [ "$s_max" = "4" ]  || r+="maxReplicas=${s_max:-absent}(≠4); "
  [ "$s_cpu" = "50" ] || r+="cible CPU=${s_cpu:-absent}(≠50); "
  fail 4 "T5a staging — HPA api-gw (min2 max4 50% CPU)" $d "${r%; }"
fi

p_min=$(kubectl -n api-gw-prod get hpa api-gw -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
p_max=$(kubectl -n api-gw-prod get hpa api-gw -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)
p_cpu=$(kubectl -n api-gw-prod get hpa api-gw -o jsonpath='{.spec.metrics[?(@.type=="Resource")].resource.target.averageUtilization}' 2>/dev/null)
if [ "$p_min" = "2" ] && [ "$p_max" = "6" ] && [ "$p_cpu" = "50" ]; then
  pass 4 "T5b prod — HPA api-gw min2 / max6 / cible CPU 50%" $d
else
  r=""
  [ "$p_min" = "2" ]  || r+="minReplicas=${p_min:-absent}(≠2); "
  [ "$p_max" = "6" ]  || r+="maxReplicas=${p_max:-absent}(≠6); "
  [ "$p_cpu" = "50" ] || r+="cible CPU=${p_cpu:-absent}(≠50); "
  fail 4 "T5b prod — HPA api-gw (min2 max6 50% CPU)" $d "${r%; }"
fi

cm_s=$(kubectl -n api-gw-staging get configmap scaling-config -o name 2>/dev/null)
cm_p=$(kubectl -n api-gw-prod    get configmap scaling-config -o name 2>/dev/null)
if [ -z "$cm_s" ] && [ -z "$cm_p" ]; then
  pass 4 "T5c ConfigMap — scaling-config supprimée (staging + prod)" $d
else
  r=""
  [ -z "$cm_s" ] || r+="scaling-config encore présente en staging; "
  [ -z "$cm_p" ] || r+="scaling-config encore présente en prod; "
  fail 4 "T5c ConfigMap — supprimer scaling-config des 2 ns" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 10 "💾 Storage"

# T6 — PV (4) + PVC bound (3) + Deployment monte le PVC (3)
d=STO
pv_cap=$(kubectl get pv data-pv -o jsonpath='{.spec.capacity.storage}' 2>/dev/null)
pv_am=$(kubectl get pv data-pv -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null)
pv_hp=$(kubectl get pv data-pv -o jsonpath='{.spec.hostPath.path}' 2>/dev/null)
pv_sc=$(kubectl get pv data-pv -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
pv_ph=$(kubectl get pv data-pv -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$pv_cap" = "1Gi" ] && [ "$pv_am" = "ReadWriteOnce" ] && [ "$pv_hp" = "/mnt/data-vol" ] && [ -z "$pv_sc" ] && [ "$pv_ph" = "Bound" ]; then
  pass 4 "T6a PV — data-pv 1Gi RWO hostPath /mnt/data-vol sans SC (Bound)" $d
else
  r=""
  [ "$pv_cap" = "1Gi" ]              || r+="capacity=${pv_cap:-absent}(≠1Gi); "
  [ "$pv_am" = "ReadWriteOnce" ]     || r+="accessMode=${pv_am:-absent}(≠RWO); "
  [ "$pv_hp" = "/mnt/data-vol" ]     || r+="hostPath=${pv_hp:-absent}; "
  [ -z "$pv_sc" ]                     || r+="storageClassName défini ('$pv_sc'); "
  [ "$pv_ph" = "Bound" ]             || r+="phase=${pv_ph:-absent}(≠Bound); "
  fail 4 "T6a PV — data-pv (1Gi RWO hostPath /mnt/data-vol, sans SC, Bound)" $d "${r%; }"
fi

pvc_ph=$(kubectl -n storage-app get pvc data-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
pvc_vol=$(kubectl -n storage-app get pvc data-pvc -o jsonpath='{.spec.volumeName}' 2>/dev/null)
pvc_req=$(kubectl -n storage-app get pvc data-pvc -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
if [ "$pvc_ph" = "Bound" ] && [ "$pvc_vol" = "data-pv" ] && [ "$pvc_req" = "1Gi" ]; then
  pass 3 "T6b PVC — data-pvc 1Gi Bound au PV data-pv" $d
else
  r=""
  [ "$pvc_req" = "1Gi" ]  || r+="request=${pvc_req:-absent}(≠1Gi); "
  [ "$pvc_ph" = "Bound" ] || r+="phase=${pvc_ph:-absent}(≠Bound); "
  [ "$pvc_vol" = "data-pv" ] || r+="lié à '${pvc_vol:-rien}' (≠data-pv); "
  fail 3 "T6b PVC — data-pvc (1Gi RWO, Bound à data-pv)" $d "${r%; }"
fi

dep_img=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
dep_claim=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null)
dep_mp=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/var/www/data")].mountPath}' 2>/dev/null)
dep_avail=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
if [ "$dep_img" = "httpd:2-alpine" ] && [ "$dep_claim" = "data-pvc" ] && [ "$dep_mp" = "/var/www/data" ] && [ -n "$dep_avail" ] && [ "$dep_avail" -ge 1 ]; then
  pass 3 "T6c Deployment — webstore (httpd:2-alpine) monte data-pvc sur /var/www/data" $d
else
  r=""
  [ "$dep_img" = "httpd:2-alpine" ] || r+="image=${dep_img:-absent}; "
  [ "$dep_claim" = "data-pvc" ]     || r+="volume PVC=${dep_claim:-aucun}(≠data-pvc); "
  [ "$dep_mp" = "/var/www/data" ]   || r+="mountPath /var/www/data absent; "
  { [ -n "$dep_avail" ] && [ "$dep_avail" -ge 1 ]; } || r+="aucun Pod disponible; "
  fail 3 "T6c Deployment — webstore monte data-pvc sur /var/www/data (httpd:2-alpine)" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom OBS 10 "📊 Observabilité (metrics-server)"

# T7 — scripts kubectl top : node.sh (5) + pod.sh (5)
#   NB : exécute les scripts du candidat (kubectl top = lecture seule, bénin).
d=OBS
NODE_SH="$BASE/node.sh"
POD_SH="$BASE/pod.sh"
if [ -f "$NODE_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+no' "$NODE_SH" \
   && bash "$NODE_SH" >/tmp/ex03-node.out 2>/dev/null && [ -s /tmp/ex03-node.out ]; then
  pass 5 "T7a node.sh — usage ressources des nodes (kubectl top nodes)" $d
else
  r=""
  [ -f "$NODE_SH" ] || r+="node.sh absent; "
  { [ -f "$NODE_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+no' "$NODE_SH"; } || r+="n'invoque pas 'kubectl top nodes'; "
  fail 5 "T7a node.sh — script d'usage ressources des nodes" $d "${r%; }"
fi

if [ -f "$POD_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+po' "$POD_SH" \
   && grep -qi -- '--containers' "$POD_SH" \
   && bash "$POD_SH" >/tmp/ex03-pod.out 2>/dev/null; then
  pass 5 "T7b pod.sh — usage ressources des Pods ET conteneurs (--containers)" $d
else
  r=""
  [ -f "$POD_SH" ] || r+="pod.sh absent; "
  { [ -f "$POD_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+po' "$POD_SH"; } || r+="n'invoque pas 'kubectl top pod'; "
  { [ -f "$POD_SH" ] && grep -qi -- '--containers' "$POD_SH"; } || r+="option --containers manquante; "
  fail 5 "T7b pod.sh — script d'usage ressources Pods + conteneurs" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom NODE 10 "🔧 Cycle de vie des nœuds (kubeadm)"

# T8a — commande de jonction générée depuis le control plane (3 + 2)
d=NODE
JOIN="$BASE/join-command.txt"
if [ -f "$JOIN" ] \
   && grep -q 'kubeadm join' "$JOIN" \
   && grep -q ':6443' "$JOIN" \
   && grep -q -- '--token' "$JOIN" \
   && grep -q -- '--discovery-token-ca-cert-hash sha256:' "$JOIN"; then
  pass 3 "T8a join-command.txt — commande kubeadm join complète (endpoint + token + hash CA)" $d
else
  r=""
  [ -f "$JOIN" ] || r+="join-command.txt absent; "
  { [ -f "$JOIN" ] && grep -q 'kubeadm join' "$JOIN"; } || r+="pas de 'kubeadm join'; "
  { [ -f "$JOIN" ] && grep -q ':6443' "$JOIN"; } || r+="endpoint API (:6443) manquant; "
  { [ -f "$JOIN" ] && grep -q -- '--token' "$JOIN"; } || r+="--token manquant; "
  { [ -f "$JOIN" ] && grep -q -- '--discovery-token-ca-cert-hash sha256:' "$JOIN"; } || r+="hash CA (--discovery-token-ca-cert-hash) manquant; "
  fail 3 "T8a join-command.txt — commande de jonction kubeadm complète" $d "${r%; }"
fi

# token réellement généré : le Secret bootstrap-token-<id> doit exister (lecture déterministe)
tok=$( [ -f "$JOIN" ] && grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' "$JOIN" | head -1 )
tokid="${tok%%.*}"
if [ -n "$tok" ] && kubectl -n kube-system get secret "bootstrap-token-$tokid" >/dev/null 2>&1; then
  pass 2 "T8a token — le token de la commande existe réellement dans le cluster" $d
else
  fail 2 "T8a token — token réel généré via kubeadm (Secret bootstrap-token présent)" $d \
    "$( [ -n "$tok" ] && echo "token '$tok' introuvable (bootstrap-token-$tokid absent — expiré ? inventé ?)" || echo "aucun token au format xxxxxx.xxxxxxxxxxxxxxxx dans le fichier" )"
fi

# T8b — runbook d'upgrade d'un worker (3 + 2)
UPN="$BASE/upgrade-node.sh"
if [ -f "$UPN" ] && grep -Eqi 'kubeadm[[:space:]]+upgrade[[:space:]]+node' "$UPN"; then
  pass 3 "T8b upgrade-node.sh — utilise 'kubeadm upgrade node' (variante worker, ≠ apply)" $d
else
  r=""
  [ -f "$UPN" ] || r+="upgrade-node.sh absent; "
  { [ -f "$UPN" ] && grep -Eqi 'kubeadm[[:space:]]+upgrade[[:space:]]+node' "$UPN"; } || r+="pas de 'kubeadm upgrade node' (un worker n'utilise pas 'upgrade apply'); "
  fail 3 "T8b upgrade-node.sh — procédure d'upgrade d'un worker" $d "${r%; }"
fi

if [ -f "$UPN" ] && grep -Eqi 'restart[[:space:]]+kubelet|kubelet[[:space:]]+restart' "$UPN" \
   && grep -Eqi 'apt-mark|apt-get[[:space:]]+install|kubelet=' "$UPN"; then
  pass 2 "T8b upgrade-node.sh — met à jour le paquet kubelet puis redémarre le service" $d
else
  r=""
  { [ -f "$UPN" ] && grep -Eqi 'apt-mark|apt-get[[:space:]]+install|kubelet=' "$UPN"; } || r+="pas de mise à jour du paquet kubelet (apt-mark/apt-get); "
  { [ -f "$UPN" ] && grep -Eqi 'restart[[:space:]]+kubelet|kubelet[[:space:]]+restart' "$UPN"; } || r+="pas de redémarrage du kubelet (systemctl restart kubelet); "
  fail 2 "T8b upgrade-node.sh — mise à jour + redémarrage du kubelet" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom APIACC 10 "🔐 API Kubernetes depuis un Pod"

# T9a — Pod utilisant la ServiceAccount (5)
d=APIACC
img=$(kubectl -n project-audit get pod secret-probe -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
sa=$(kubectl -n project-audit get pod secret-probe -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
phase=$(kubectl -n project-audit get pod secret-probe -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$img" = "nginx:1-alpine" ] && [ "$sa" = "probe-sa" ] && [ "$phase" = "Running" ]; then
  pass 5 "T9a Pod secret-probe — nginx:1-alpine, ServiceAccount probe-sa, Running" $d
else
  r=""
  [ "$img" = "nginx:1-alpine" ] || r+="image=${img:-absent}(≠nginx:1-alpine); "
  [ "$sa" = "probe-sa" ]        || r+="serviceAccountName=${sa:-défaut}(≠probe-sa); "
  [ "$phase" = "Running" ]      || r+="phase=${phase:-absent}; "
  fail 5 "T9a Pod secret-probe — nginx:1-alpine utilisant la SA probe-sa" $d "${r%; }"
fi

# T9b — résultat de la requête API (SecretList JSON) écrit dans le fichier (3 + 2)
RES="$BASE/secrets.json"
if [ -f "$RES" ] && grep -q '"kind"' "$RES" && grep -q 'SecretList' "$RES"; then
  pass 3 "T9b secrets.json — réponse de l'API : liste de Secrets (kind SecretList)" $d
else
  r=""
  [ -f "$RES" ] || r+="secrets.json absent; "
  { [ -f "$RES" ] && grep -q 'SecretList' "$RES"; } || r+="pas une réponse SecretList de l'API; "
  fail 3 "T9b secrets.json — réponse JSON de l'API (SecretList)" $d "${r%; }"
fi

if [ -f "$RES" ] && grep -q 'audit-key' "$RES"; then
  pass 2 "T9b secrets.json — contient bien le Secret audit-key du namespace" $d
else
  fail 2 "T9b secrets.json — le Secret 'audit-key' doit apparaître dans la réponse" $d \
    "$( [ -f "$RES" ] && echo "audit-key introuvable (mauvais namespace ? droits SA insuffisants ?)" || echo "secrets.json absent" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SCHED 10 "🛰️  DaemonSet & scheduling"

# T10 — DaemonSet sur tous les nœuds (4 image/labels + 3 requests + 3 planifié partout)
d=SCHED
nnodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
ds_img=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
ds_lid=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.metadata.labels.id}' 2>/dev/null)
ds_luuid=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.metadata.labels.uuid}' 2>/dev/null)
if [ "$ds_img" = "httpd:2-alpine" ] && [ "$ds_lid" = "log-harvester" ] && [ "$ds_luuid" = "7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64" ]; then
  pass 4 "T10a DaemonSet log-harvester — httpd:2-alpine + labels id/uuid" $d
else
  r=""
  [ "$ds_img" = "httpd:2-alpine" ] || r+="image=${ds_img:-absent}(≠httpd:2-alpine); "
  [ "$ds_lid" = "log-harvester" ] || r+="label id=${ds_lid:-absent}; "
  [ "$ds_luuid" = "7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64" ] || r+="label uuid incorrect; "
  fail 4 "T10a DaemonSet log-harvester — image + labels id/uuid" $d "${r%; }"
fi

ds_cpu=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
ds_mem=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)
if [ "$ds_cpu" = "15m" ] && [ "$ds_mem" = "20Mi" ]; then
  pass 3 "T10b requests — cpu 15m + memory 20Mi" $d
else
  fail 3 "T10b requests — cpu 15m + memory 20Mi" $d "cpu=${ds_cpu:-absent}, mem=${ds_mem:-absent}"
fi

ds_des=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
ds_rdy=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.status.numberReady}' 2>/dev/null)
if [ -n "$ds_des" ] && [ "$ds_des" = "$nnodes" ] && [ "${ds_rdy:-0}" = "$nnodes" ]; then
  pass 3 "T10c planification — un Pod Ready sur les $nnodes nœuds (control-plane toléré)" $d
else
  fail 3 "T10c planification — un Pod Ready sur tous les nœuds (control-plane compris)" $d \
    "désirés=${ds_des:-0}/$nnodes, prêts=${ds_rdy:-0}/$nnodes (toleration control-plane manquante ?)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom AFFIN 10 "🧲 Affinité & multi-conteneurs"

# T11 — Deployment 2 conteneurs + podAntiAffinity (4 + 3 + 3)
d=AFFIN
rep=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.replicas}' 2>/dev/null)
dlid=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.metadata.labels.id}' 2>/dev/null)
c0n=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)
c0i=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
c1n=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.spec.containers[1].name}' 2>/dev/null)
c1i=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.spec.containers[1].image}' 2>/dev/null)
if [ "$rep" = "3" ] && [ "$dlid" = "edge-node" ] \
   && [ "$c0n" = "main" ] && [ "$c0i" = "nginx:1-alpine" ] \
   && [ "$c1n" = "sidecar" ] && [ "$c1i" = "registry.k8s.io/pause:3.10" ]; then
  pass 4 "T11a Deployment edge-cache — 3 replicas, label id=edge-node, conteneurs main+sidecar" $d
else
  r=""
  [ "$rep" = "3" ] || r+="replicas=${rep:-absent}(≠3); "
  [ "$dlid" = "edge-node" ] || r+="label id=${dlid:-absent}; "
  { [ "$c0n" = "main" ] && [ "$c0i" = "nginx:1-alpine" ]; } || r+="conteneur1 main/nginx:1-alpine KO (${c0n:-?}/${c0i:-?}); "
  { [ "$c1n" = "sidecar" ] && [ "$c1i" = "registry.k8s.io/pause:3.10" ]; } || r+="conteneur2 sidecar/pause:3.10 KO (${c1n:-?}/${c1i:-?}); "
  fail 4 "T11a Deployment edge-cache — 3 replicas + label + 2 conteneurs" $d "${r%; }"
fi

tk=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey}' 2>/dev/null)
if [ "$tk" = "kubernetes.io/hostname" ]; then
  pass 3 "T11b anti-affinité — podAntiAffinity requise sur topologyKey kubernetes.io/hostname" $d
else
  fail 3 "T11b anti-affinité — podAntiAffinity (topologyKey kubernetes.io/hostname)" $d "topologyKey=${tk:-absent}"
fi

run=$(kubectl -n project-batch get pods -l id=edge-node --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
pend=$(kubectl -n project-batch get pods -l id=edge-node --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$run" = "2" ] && [ "${pend:-0}" -ge 1 ]; then
  pass 3 "T11c répartition — 2 Pods Running (1/nœud) + 1 Pending (3e non planifiable)" $d
else
  fail 3 "T11c répartition — 2 Running (1 par nœud) + 1 Pending" $d "Running=${run:-0} (attendu 2), Pending=${pend:-0} (attendu ≥1)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom CERTS 10 "🔐 Certificats du cluster"

# T13 — expiration apiserver (5) + commande de renew (5)
d=CERTS
EXP="$BASE/apiserver-expiration"
# Vérité terrain : année d'expiration du certificat apiserver (openssl sur le vrai cert)
exp_year=$(sudo -n openssl x509 -noout -enddate -in /etc/kubernetes/pki/apiserver.crt 2>/dev/null | grep -oE '20[0-9]{2}')
if [ -f "$EXP" ] && [ -s "$EXP" ] && [ -n "$exp_year" ] && grep -q "$exp_year" "$EXP"; then
  pass 5 "T13a apiserver-expiration — date d'expiration du cert kube-apiserver ($exp_year)" $d
else
  r=""
  [ -f "$EXP" ] || r+="apiserver-expiration absent; "
  { [ -f "$EXP" ] && [ -s "$EXP" ]; } || r+="fichier vide; "
  { [ -f "$EXP" ] && grep -q "${exp_year:-__}" "$EXP"; } || r+="ne contient pas l'année d'expiration attendue ($exp_year); "
  fail 5 "T13a apiserver-expiration — date d'expiration du cert kube-apiserver" $d "${r%; }"
fi

RNW="$BASE/renew-apiserver.sh"
if [ -f "$RNW" ] && grep -Eq 'kubeadm[[:space:]]+certs[[:space:]]+renew[[:space:]]+apiserver' "$RNW"; then
  pass 5 "T13b renew-apiserver.sh — commande 'kubeadm certs renew apiserver'" $d
else
  r=""
  [ -f "$RNW" ] || r+="renew-apiserver.sh absent; "
  { [ -f "$RNW" ] && grep -Eq 'kubeadm[[:space:]]+certs[[:space:]]+renew[[:space:]]+apiserver' "$RNW"; } || r+="pas de 'kubeadm certs renew apiserver'; "
  fail 5 "T13b renew-apiserver.sh — commande de renouvellement kubeadm" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom NETEG 10 "🛡️  Réseau — NetworkPolicy egress"

# T14 — egress backend → cache-a:6379 / cache-b:5432 (4 sélecteur+type / 3 / 3)
d=NETEG
np_pod=$(kubectl -n project-mesh get netpol np-egress -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null)
np_types=$(kubectl -n project-mesh get netpol np-egress -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null)
if [ "$np_pod" = "backend" ] && printf '%s' "$np_types" | grep -qw Egress; then
  pass 4 "T14a np-egress — sélectionne app=backend, policyTypes Egress" $d
else
  r=""
  [ "$np_pod" = "backend" ] || r+="podSelector app=${np_pod:-absent}(≠backend); "
  printf '%s' "$np_types" | grep -qw Egress || r+="policyTypes sans Egress (=${np_types:-absent}); "
  fail 4 "T14a np-egress — podSelector app=backend + policyTypes Egress" $d "${r%; }"
fi

# paires (cible:port) par règle egress — une règle correcte associe une seule cible à son port
pairs=$(kubectl -n project-mesh get netpol np-egress -o jsonpath='{range .spec.egress[*]}{.to[0].podSelector.matchLabels.app}:{.ports[0].port}{"\n"}{end}' 2>/dev/null)
if printf '%s' "$pairs" | grep -qx 'cache-a:6379'; then
  pass 3 "T14b egress — autorise app=cache-a sur le port 6379" $d
else
  fail 3 "T14b egress — app=cache-a sur le port 6379" $d "règles (cible:port) = $(printf '%s' "$pairs" | tr '\n' ' ')"
fi
if printf '%s' "$pairs" | grep -qx 'cache-b:5432'; then
  pass 3 "T14c egress — autorise app=cache-b sur le port 5432" $d
else
  fail 3 "T14c egress — app=cache-b sur le port 5432" $d "règles (cible:port) = $(printf '%s' "$pairs" | tr '\n' ' ')"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom CRICTL 10 "🔎  Debug — runtime de conteneurs (crictl)"

# T16 — container-info.txt (ID + runtimeType) + container.log (4 ID / 3 runtime / 3 log)
d=CRICTL
info="$BASE/container-info.txt"
logf="$BASE/container.log"
if [ -f "$info" ] && grep -qiE '[0-9a-f]{12,}' "$info"; then
  pass 4 "T16a container-info.txt — contient un ID de conteneur (hexadécimal ≥12)" $d
else
  fail 4 "T16a container-info.txt — ID de conteneur hexadécimal" $d "fichier absent ou sans ID hex (≥ 12 car.)"
fi
if [ -f "$info" ] && grep -qiE 'runc|runtimeType' "$info"; then
  pass 3 "T16b container-info.txt — type de runtime (runc / runtimeType)" $d
else
  fail 3 "T16b container-info.txt — type de runtime (info.runtimeType)" $d "le champ runtimeType (ex. io.containerd.runc.v2) est absent"
fi
if [ -f "$logf" ]; then
  pass 3 "T16c container.log — logs du conteneur capturés" $d
else
  fail 3 "T16c container.log — fichier de logs" $d "fichier /opt/exam-03/container.log absent"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom GWAPI 10 "🚪  Gateway API — routage HTTP"

# T12 — HTTPRoute route-splitter (4 parentRefs / 3 chemins / 3 en-tête)
d=GWAPI
if kubectl -n project-edge get httproute route-splitter >/dev/null 2>&1; then
  prefs=$(kubectl -n project-edge get httproute route-splitter -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$prefs" | grep -qw edge-gw; then
    pass 3 "T12a route-splitter — rattachée au Gateway edge-gw (parentRefs)" $d
  else
    fail 3 "T12a route-splitter — parentRefs vers edge-gw" $d "parentRefs = ${prefs:-vide}"
  fi

  paths=$(kubectl -n project-edge get httproute route-splitter -o jsonpath='{range .spec.rules[*].matches[*]}{.path.value}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$paths" | grep -qx '/web' && printf '%s' "$paths" | grep -qx '/svc'; then
    pass 3 "T12b route-splitter — routes par préfixe /web et /svc" $d
  else
    fail 3 "T12b route-splitter — préfixes /web et /svc" $d "chemins trouvés = $(printf '%s' "$paths" | tr '\n' ' ')"
  fi

  # paires (path|header) par match : un match combinant path ET header applique un ET logique
  ph=$(kubectl -n project-edge get httproute route-splitter -o jsonpath='{range .spec.rules[*].matches[*]}{.path.value}|{.headers[0].name}={.headers[0].value}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$ph" | grep -qix '/shop|X-Tier=premium'; then
    pass 2 "T12c route-splitter — /shop + en-tête X-Tier: premium dans le même match (ET logique)" $d
  else
    fail 2 "T12c route-splitter — /shop conditionné par X-Tier: premium (même match)" $d "matches (path|header) = $(printf '%s' "$ph" | tr '\n' ' ')"
  fi
  if printf '%s' "$ph" | grep -qx '/shop|='; then
    pass 2 "T12d route-splitter — catch-all /shop (sans en-tête) vers le backend par défaut" $d
  else
    fail 2 "T12d route-splitter — /shop catch-all (sinon)" $d "aucun match /shop sans en-tête (fallback) trouvé"
  fi
else
  fail 3 "T12a route-splitter — rattachée au Gateway edge-gw (parentRefs)" $d "HTTPRoute route-splitter absente de project-edge"
  fail 3 "T12b route-splitter — préfixes /web et /svc" $d "HTTPRoute absente"
  fail 2 "T12c route-splitter — /shop + X-Tier: premium (même match)" $d "HTTPRoute absente"
  fail 2 "T12d route-splitter — /shop catch-all" $d "HTTPRoute absente"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom COREDNS 10 "🧭  CoreDNS — domaine personnalisé"

# T15 — sauvegarde + Corefile avec cka.local (4 backup / 3 mention / 3 plugin kubernetes)
d=COREDNS
bk="$BASE/coredns_original.yaml"
if [ -f "$bk" ] && grep -qi 'kind.*configmap' "$bk" && grep -q 'Corefile' "$bk"; then
  pass 4 "T15a coredns_original.yaml — sauvegarde de la ConfigMap coredns" $d
else
  fail 4 "T15a coredns_original.yaml — sauvegarde valide de la ConfigMap coredns" $d "fichier absent ou pas la ConfigMap coredns (kind ConfigMap + clé Corefile)"
fi
cf=$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' 2>/dev/null)
if printf '%s' "$cf" | grep -q 'cka\.local'; then
  pass 3 "T15b Corefile — le domaine cka.local est déclaré" $d
else
  fail 3 "T15b Corefile — domaine cka.local" $d "le Corefile de la ConfigMap coredns ne contient pas cka.local"
fi
if printf '%s' "$cf" | grep -qE 'kubernetes.*cka\.local'; then
  pass 3 "T15c Corefile — cka.local résolu par le plugin kubernetes" $d
else
  fail 3 "T15c Corefile — cka.local sur la ligne du plugin kubernetes" $d "cka.local doit être ajouté aux zones du plugin 'kubernetes' (ex. kubernetes cluster.local cka.local …)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom ETCD 9 "🗄️  etcd — introspection"

# T17 — etcd-info.txt : clé privée / expiration cert / client-cert-auth (3/3/3)
d=ETCD
ei="$BASE/etcd-info.txt"
if [ -f "$ei" ] && grep -qE 'server\.key|etcd/.*\.key' "$ei"; then
  pass 3 "T17a etcd-info.txt — emplacement de la clé privée serveur (server.key)" $d
else
  fail 3 "T17a etcd-info.txt — chemin de la clé privée serveur d'etcd" $d "le chemin de server.key (pki/etcd/server.key) est absent du fichier"
fi
if [ -f "$ei" ] && grep -qE '20[0-9]{2}' "$ei"; then
  pass 3 "T17b etcd-info.txt — date d'expiration du certificat serveur" $d
else
  fail 3 "T17b etcd-info.txt — date d'expiration du cert serveur etcd" $d "aucune année d'expiration (ex. 2027) trouvée dans le fichier"
fi
if [ -f "$ei" ] && grep -qiE 'client.?cert.?auth|auth.*client' "$ei" && grep -qiE '\btrue\b|\byes\b|\boui\b|enabled|activ' "$ei"; then
  pass 3 "T17c etcd-info.txt — authentification par certificat client activée" $d
else
  fail 3 "T17c etcd-info.txt — état de l'authentification par certificat client" $d "il manque la mention client-cert-auth et sa valeur (activée/true/oui)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom KPROXY 8 "🔀  kube-proxy & iptables"

# T18 — Pod+Service + capture des règles iptables (4 objets / 4 capture)
d=KPROXY
pod_ok=0; svc_ok=0
[ "$(kubectl -n project-proxy get pod p-proxy -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && pod_ok=1
pport="$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)"
ptport="$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)"
ptype="$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.type}' 2>/dev/null)"
[ "$pport" = "3100" ] && [ "$ptport" = "80" ] && [ "$ptype" = "ClusterIP" ] && svc_ok=1
if [ "$pod_ok" = 1 ] && [ "$svc_ok" = 1 ]; then
  pass 4 "T18a Pod p-proxy (Running) + Service proxy-svc ClusterIP 3100→80" $d
else
  fail 4 "T18a Pod p-proxy + Service proxy-svc (ClusterIP 3100→80)" $d "le Pod p-proxy n'est pas Running ou proxy-svc ne mappe pas 3100→80 en ClusterIP"
fi
ipf="$BASE/iptables.txt"
cip="$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
if [ -f "$ipf" ] && grep -qiE 'KUBE-(SVC|SEP|SERVICES)' "$ipf" && { grep -qi 'proxy-svc' "$ipf" || { [ -n "$cip" ] && grep -q "$cip" "$ipf"; }; }; then
  pass 4 "T18b iptables.txt — règles kube-proxy du Service capturées" $d
else
  fail 4 "T18b iptables.txt — règles iptables (nat) du Service proxy-svc" $d "le fichier ne contient pas les chaînes KUBE-SVC ni le clusterIP/nom du Service"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SVCCIDR 10 "🌐  Service CIDR (multi-range)"

# T19 — ServiceCIDR additif + Service dans la nouvelle plage (4 CIDR / 4 IP / 2 base)
d=SVCCIDR
sc_cidrs="$(kubectl get servicecidr extra-range -o jsonpath='{.spec.cidrs}' 2>/dev/null)"
if echo "$sc_cidrs" | grep -q '12.64.0.0/12'; then
  pass 4 "T19a ServiceCIDR extra-range couvre 12.64.0.0/12" $d
else
  fail 4 "T19a ServiceCIDR extra-range (12.64.0.0/12)" $d "l'objet ServiceCIDR extra-range est absent ou ne couvre pas 12.64.0.0/12"
fi
cip2="$(kubectl -n project-range get svc range-svc2 -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
if echo "$cip2" | grep -qE '^12\.(6[4-9]|7[0-9])\.[0-9]+\.[0-9]+$'; then
  pass 4 "T19b range-svc2 — clusterIP dans la nouvelle plage 12.64.0.0/12" $d
else
  fail 4 "T19b range-svc2 — clusterIP issue de 12.64.0.0/12" $d "range-svc2 n'a pas de clusterIP comprise dans 12.64.0.0/12"
fi
rp_ok=0; rs_ok=0
[ "$(kubectl -n project-range get pod range-probe -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && rp_ok=1
[ "$(kubectl -n project-range get svc range-svc -o jsonpath='{.spec.type}' 2>/dev/null)" = "ClusterIP" ] && rs_ok=1
if [ "$rp_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
  pass 2 "T19c Pod range-probe (Running) + Service range-svc (ClusterIP)" $d
else
  fail 2 "T19c Pod range-probe + Service range-svc (ClusterIP)" $d "le Pod range-probe n'est pas Running ou range-svc n'est pas un ClusterIP"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Récapitulatif
TOTAL=0; GOT=0
printf "\n────────────────────────────────────────────────────────\n"
printf "Sous-totaux par domaine :\n"
declare -A DOM_LABEL=( [KUBECFG]="Cluster Architecture & kubeconfig" [PKG]="Packaging & Helm" [WL]="Workloads & Scheduling" [AUTO]="HPA & Kustomize" [STO]="Storage" [OBS]="Observabilité" [NODE]="Cycle de vie des nœuds" [APIACC]="API depuis un Pod" [SCHED]="DaemonSet & tolérations" [AFFIN]="Affinité & multi-conteneurs" [GWAPI]="Gateway API" [CERTS]="Certificats du cluster" [NETEG]="NetworkPolicy egress" [COREDNS]="CoreDNS" [CRICTL]="Debug crictl" [ETCD]="etcd — introspection" [KPROXY]="kube-proxy & iptables" [SVCCIDR]="Service CIDR (multi-range)" )
for k in KUBECFG PKG WL AUTO STO OBS NODE APIACC SCHED AFFIN GWAPI CERTS NETEG COREDNS CRICTL ETCD KPROXY SVCCIDR; do
  [ -n "${DOM_MAX[$k]:-}" ] || continue
  printf "  %-34s %2d / %d\n" "${DOM_LABEL[$k]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
  TOTAL=$((TOTAL + DOM_MAX[$k])); GOT=$((GOT + ${DOM_GOT[$k]:-0}))
done
printf "────────────────────────────────────────────────────────\n"
printf "SCORE TOTAL : %d / %d\n" "$GOT" "$TOTAL"
if [ "$TOTAL" -gt 0 ] && [ $((GOT*100/TOTAL)) -ge 66 ]; then
  printf "\033[32m🎉 RÉUSSI (≥ 66%%)\033[0m\n"
else
  printf "\033[31mÉCHEC (< 66%%)\033[0m\n"
fi
printf "────────────────────────────────────────────────────────\n"
