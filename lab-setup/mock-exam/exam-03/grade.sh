#!/usr/bin/env bash
# grade.sh — auto-grader for CKA mock exam #3 (targeted drills).
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-03/grade.sh"
#
# Read-only: it changes NOTHING. Prints PASS/FAIL per task
# (with the symptom observed on failure, but NEVER the solution),
# subtotal per domain and total score. Pass ≥ 66%.
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }

BASE=/opt/exam-03

# ══════════════════════════════════════════════════════════════════════════════
dom KUBECFG 7 "🏛️  Cluster Architecture & kubeconfig"

# T1 — kubeconfig extraction (3 + 2 + 2)
d=KUBECFG
KC="$BASE/kubeconfig"
OUT_CTX="$BASE/contexts"
OUT_CUR="$BASE/current-context"
OUT_CERT="$BASE/cert"

# Ground truth computed from the provided kubeconfig (single source)
exp_ctx=$(kubectl config --kubeconfig="$KC" get-contexts -o name 2>/dev/null | sort)
exp_cur=$(kubectl config --kubeconfig="$KC" view -o jsonpath='{.current-context}' 2>/dev/null)
exp_cert=$(kubectl config --kubeconfig="$KC" view --raw \
           -o jsonpath="{.users[?(@.name=='audit-user')].user.client-certificate-data}" 2>/dev/null | base64 -d 2>/dev/null)

# 1) contexts (order doesn't matter)
got_ctx=$(sort "$OUT_CTX" 2>/dev/null | sed '/^[[:space:]]*$/d')
if [ -f "$OUT_CTX" ] && [ -n "$exp_ctx" ] && [ "$got_ctx" = "$exp_ctx" ]; then
  pass 3 "T1a contexts — the 3 context names are listed" $d
else
  fail 3 "T1a contexts — write all context names (one/line)" $d \
    "$( [ -f "$OUT_CTX" ] && echo "content != expected (3 contexts)" || echo "$OUT_CTX missing" )"
fi

# 2) current-context
got_cur=$( [ -f "$OUT_CUR" ] && tr -d '[:space:]' < "$OUT_CUR" 2>/dev/null )
if [ -f "$OUT_CUR" ] && [ -n "$exp_cur" ] && [ "$got_cur" = "$exp_cur" ]; then
  pass 2 "T1b current-context — current context correct" $d
else
  fail 2 "T1b current-context — write the current context name" $d \
    "$( [ -f "$OUT_CUR" ] && echo "expected '$exp_cur', got '${got_cur:-empty}'" || echo "$OUT_CUR missing" )"
fi

# 3) decoded certificate (base64 -d)
got_cert=$(cat "$OUT_CERT" 2>/dev/null)
# comparison ignoring a possible trailing newline
if [ -f "$OUT_CERT" ] && [ -n "$exp_cert" ] \
   && [ "$(printf '%s' "$got_cert")" = "$(printf '%s' "$exp_cert")" ]; then
  pass 2 "T1c cert — audit-user's client-certificate decoded (base64 -d)" $d
else
  fail 2 "T1c cert — decode audit-user's client-certificate" $d \
    "$( [ -f "$OUT_CERT" ] && echo "content != expected decoded certificate" || echo "$OUT_CERT missing" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom PKG 8 "📦 Packaging & Helm"

# T2 — Helm cert-manager + ClusterIssuer (5 + 3)
d=PKG
rel=$(helm list -n pki -q 2>/dev/null | grep -x certman)
crd_ok=$(kubectl get crd clusterissuers.cert-manager.io -o name 2>/dev/null)
if [ -n "$rel" ] && [ -n "$crd_ok" ]; then
  pass 5 "T2a Helm — release certman installed in pki (cert-manager CRDs present)" $d
else
  r=""
  [ -n "$rel" ]    || r+="helm release 'certman' missing from ns pki; "
  [ -n "$crd_ok" ] || r+="CRD clusterissuers.cert-manager.io missing; "
  fail 5 "T2a Helm — install jetstack/cert-manager (release certman, ns pki, crds.enabled)" $d "${r%; }"
fi

ci=$(kubectl get clusterissuer selfsigned-issuer -o name 2>/dev/null)
crl=$(kubectl get clusterissuer selfsigned-issuer -o jsonpath='{.spec.selfSigned.crlDistributionPoints[0]}' 2>/dev/null)
if [ -n "$ci" ] && [ "$crl" = "http://pki.cka.local/crl" ]; then
  pass 3 "T2b ClusterIssuer — selfsigned-issuer created with crlDistributionPoints" $d
else
  r=""
  [ -n "$ci" ]                              || r+="ClusterIssuer selfsigned-issuer missing; "
  [ "$crl" = "http://pki.cka.local/crl" ]   || r+="crlDistributionPoints missing/incorrect; "
  fail 3 "T2b ClusterIssuer — create selfsigned-issuer (+ crlDistributionPoints)" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom WL 11 "🧱 Workloads & Scheduling"

# T3 — Scale a StatefulSet to 1 replica (5)
d=WL
sts_rep=$(kubectl -n project-store get statefulset store-db -o jsonpath='{.spec.replicas}' 2>/dev/null)
sts_ready=$(kubectl -n project-store get statefulset store-db -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$sts_rep" = "1" ] && [ "$sts_ready" = "1" ]; then
  pass 5 "T3 StatefulSet — store-db scaled to 1 replica (Pod ready)" $d
else
  r=""
  [ "$sts_rep" = "1" ]   || r+="spec.replicas=${sts_rep:-missing} (expected 1); "
  [ "$sts_ready" = "1" ] || r+="readyReplicas=${sts_ready:-0} (expected 1); "
  fail 5 "T3 StatefulSet — scale store-db to 1 replica (ns project-store)" $d "${r%; }"
fi

# T4 — QoS: Pods evicted first = BestEffort (6)
OUT_QOS="$BASE/qos-evicted-first.txt"
exp_qos=$(kubectl -n project-qos get pods \
            -o jsonpath='{range .items[?(@.status.qosClass=="BestEffort")]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
            | sed '/^[[:space:]]*$/d' | sort)
got_qos=$( [ -f "$OUT_QOS" ] && sort "$OUT_QOS" 2>/dev/null | sed '/^[[:space:]]*$/d' )
if [ -f "$OUT_QOS" ] && [ -n "$exp_qos" ] && [ "$got_qos" = "$exp_qos" ]; then
  pass 6 "T4 QoS — BestEffort Pods (evicted first) correctly listed" $d
else
  fail 6 "T4 QoS — list the Pods evicted first in qos-evicted-first.txt" $d \
    "$( [ -f "$OUT_QOS" ] && echo "content != expected BestEffort list" || echo "$OUT_QOS missing" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom AUTO 12 "🧩 HPA & Kustomize"

# T5 — HPA via Kustomize: staging (3) + prod (3) + cluster ConfigMap (3) + build (3)
d=AUTO
s_min=$(kubectl -n api-gw-staging get hpa api-gw -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
s_max=$(kubectl -n api-gw-staging get hpa api-gw -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)
s_cpu=$(kubectl -n api-gw-staging get hpa api-gw -o jsonpath='{.spec.metrics[?(@.type=="Resource")].resource.target.averageUtilization}' 2>/dev/null)
if [ "$s_min" = "2" ] && [ "$s_max" = "4" ] && [ "$s_cpu" = "50" ]; then
  pass 3 "T5a staging — HPA api-gw min2 / max4 / CPU target 50%" $d
else
  r=""
  [ "$s_min" = "2" ]  || r+="minReplicas=${s_min:-missing}(≠2); "
  [ "$s_max" = "4" ]  || r+="maxReplicas=${s_max:-missing}(≠4); "
  [ "$s_cpu" = "50" ] || r+="CPU target=${s_cpu:-missing}(≠50); "
  fail 3 "T5a staging — HPA api-gw (min2 max4 50% CPU)" $d "${r%; }"
fi

p_min=$(kubectl -n api-gw-prod get hpa api-gw -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
p_max=$(kubectl -n api-gw-prod get hpa api-gw -o jsonpath='{.spec.maxReplicas}' 2>/dev/null)
p_cpu=$(kubectl -n api-gw-prod get hpa api-gw -o jsonpath='{.spec.metrics[?(@.type=="Resource")].resource.target.averageUtilization}' 2>/dev/null)
if [ "$p_min" = "2" ] && [ "$p_max" = "6" ] && [ "$p_cpu" = "50" ]; then
  pass 3 "T5b prod — HPA api-gw min2 / max6 / CPU target 50%" $d
else
  r=""
  [ "$p_min" = "2" ]  || r+="minReplicas=${p_min:-missing}(≠2); "
  [ "$p_max" = "6" ]  || r+="maxReplicas=${p_max:-missing}(≠6); "
  [ "$p_cpu" = "50" ] || r+="CPU target=${p_cpu:-missing}(≠50); "
  fail 3 "T5b prod — HPA api-gw (min2 max6 50% CPU)" $d "${r%; }"
fi

cm_s=$(kubectl -n api-gw-staging get configmap scaling-config -o name 2>/dev/null)
cm_p=$(kubectl -n api-gw-prod    get configmap scaling-config -o name 2>/dev/null)
if [ -z "$cm_s" ] && [ -z "$cm_p" ]; then
  pass 3 "T5c ConfigMap — scaling-config removed from the cluster (staging + prod)" $d
else
  r=""
  [ -z "$cm_s" ] || r+="scaling-config still present in staging; "
  [ -z "$cm_p" ] || r+="scaling-config still present in prod; "
  fail 3 "T5c ConfigMap — delete scaling-config from both ns" $d "${r%; }"
fi

# T5d — Kustomize hygiene: the staging+prod build passes, the ConfigMap is removed
#        from resources (no longer in the build) and the HPA is present (not just applied by hand).
KZ="$BASE/kustomize/api-gw"
kb_stg=$(kubectl kustomize "$KZ/overlays/staging" 2>/dev/null)
kb_prd=$(kubectl kustomize "$KZ/overlays/prod"    2>/dev/null)
if [ -n "$kb_stg" ] && [ -n "$kb_prd" ] \
   && printf '%s' "$kb_prd" | grep -q 'kind: HorizontalPodAutoscaler' \
   && ! printf '%s' "$kb_stg" | grep -q 'name: scaling-config' \
   && ! printf '%s' "$kb_prd" | grep -q 'name: scaling-config'; then
  pass 3 "T5d Kustomize — staging+prod build OK, ConfigMap removed from resources, HPA present" $d
else
  r=""
  { [ -n "$kb_stg" ] && [ -n "$kb_prd" ]; } || r+="kubectl kustomize fails (build error); "
  printf '%s' "$kb_prd" | grep -q 'kind: HorizontalPodAutoscaler' || r+="HPA missing from prod build; "
  printf '%s' "$kb_stg" | grep -q 'name: scaling-config' && r+="scaling-config still in staging build (remove configmap.yaml from resources); "
  printf '%s' "$kb_prd" | grep -q 'name: scaling-config' && r+="scaling-config still in prod build; "
  fail 3 "T5d Kustomize — clean build (ConfigMap removed from resources, HPA present)" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 10 "💾 Storage"

# T6 — PV (4) + PVC bound (3) + Deployment mounts the PVC (3)
d=STO
pv_cap=$(kubectl get pv data-pv -o jsonpath='{.spec.capacity.storage}' 2>/dev/null)
pv_am=$(kubectl get pv data-pv -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null)
pv_hp=$(kubectl get pv data-pv -o jsonpath='{.spec.hostPath.path}' 2>/dev/null)
pv_sc=$(kubectl get pv data-pv -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
pv_ph=$(kubectl get pv data-pv -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$pv_cap" = "1Gi" ] && [ "$pv_am" = "ReadWriteOnce" ] && [ "$pv_hp" = "/mnt/data-vol" ] && [ -z "$pv_sc" ] && [ "$pv_ph" = "Bound" ]; then
  pass 4 "T6a PV — data-pv 1Gi RWO hostPath /mnt/data-vol without SC (Bound)" $d
else
  r=""
  [ "$pv_cap" = "1Gi" ]              || r+="capacity=${pv_cap:-missing}(≠1Gi); "
  [ "$pv_am" = "ReadWriteOnce" ]     || r+="accessMode=${pv_am:-missing}(≠RWO); "
  [ "$pv_hp" = "/mnt/data-vol" ]     || r+="hostPath=${pv_hp:-missing}; "
  [ -z "$pv_sc" ]                     || r+="storageClassName set ('$pv_sc'); "
  [ "$pv_ph" = "Bound" ]             || r+="phase=${pv_ph:-missing}(≠Bound); "
  fail 4 "T6a PV — data-pv (1Gi RWO hostPath /mnt/data-vol, without SC, Bound)" $d "${r%; }"
fi

pvc_ph=$(kubectl -n storage-app get pvc data-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
pvc_vol=$(kubectl -n storage-app get pvc data-pvc -o jsonpath='{.spec.volumeName}' 2>/dev/null)
pvc_req=$(kubectl -n storage-app get pvc data-pvc -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
if [ "$pvc_ph" = "Bound" ] && [ "$pvc_vol" = "data-pv" ] && [ "$pvc_req" = "1Gi" ]; then
  pass 3 "T6b PVC — data-pvc 1Gi Bound to the PV data-pv" $d
else
  r=""
  [ "$pvc_req" = "1Gi" ]  || r+="request=${pvc_req:-missing}(≠1Gi); "
  [ "$pvc_ph" = "Bound" ] || r+="phase=${pvc_ph:-missing}(≠Bound); "
  [ "$pvc_vol" = "data-pv" ] || r+="bound to '${pvc_vol:-none}' (≠data-pv); "
  fail 3 "T6b PVC — data-pvc (1Gi RWO, Bound to data-pv)" $d "${r%; }"
fi

dep_img=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
dep_claim=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null)
dep_mp=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=="/var/www/data")].mountPath}' 2>/dev/null)
dep_avail=$(kubectl -n storage-app get deploy webstore -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
if [ "$dep_img" = "httpd:2-alpine" ] && [ "$dep_claim" = "data-pvc" ] && [ "$dep_mp" = "/var/www/data" ] && [ -n "$dep_avail" ] && [ "$dep_avail" -ge 1 ]; then
  pass 3 "T6c Deployment — webstore (httpd:2-alpine) mounts data-pvc at /var/www/data" $d
else
  r=""
  [ "$dep_img" = "httpd:2-alpine" ] || r+="image=${dep_img:-missing}; "
  [ "$dep_claim" = "data-pvc" ]     || r+="PVC volume=${dep_claim:-none}(≠data-pvc); "
  [ "$dep_mp" = "/var/www/data" ]   || r+="mountPath /var/www/data missing; "
  { [ -n "$dep_avail" ] && [ "$dep_avail" -ge 1 ]; } || r+="no Pod available; "
  fail 3 "T6c Deployment — webstore mounts data-pvc at /var/www/data (httpd:2-alpine)" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom OBS 10 "📊 Observability (metrics-server)"

# T7 — kubectl top scripts: node.sh (5) + pod.sh (5)
#   NB: runs the candidate's scripts (kubectl top = read-only, harmless).
d=OBS
NODE_SH="$BASE/node.sh"
POD_SH="$BASE/pod.sh"
if [ -f "$NODE_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+no' "$NODE_SH" \
   && bash "$NODE_SH" >/tmp/ex03-node.out 2>/dev/null && [ -s /tmp/ex03-node.out ]; then
  pass 5 "T7a node.sh — node resource usage (kubectl top nodes)" $d
else
  r=""
  [ -f "$NODE_SH" ] || r+="node.sh missing; "
  { [ -f "$NODE_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+no' "$NODE_SH"; } || r+="does not invoke 'kubectl top nodes'; "
  fail 5 "T7a node.sh — node resource usage script" $d "${r%; }"
fi

if [ -f "$POD_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+po' "$POD_SH" \
   && grep -qi -- '--containers' "$POD_SH" \
   && bash "$POD_SH" >/tmp/ex03-pod.out 2>/dev/null; then
  pass 5 "T7b pod.sh — Pods AND containers resource usage (--containers)" $d
else
  r=""
  [ -f "$POD_SH" ] || r+="pod.sh missing; "
  { [ -f "$POD_SH" ] && grep -Eqi 'kubectl[[:space:]]+top[[:space:]]+po' "$POD_SH"; } || r+="does not invoke 'kubectl top pod'; "
  { [ -f "$POD_SH" ] && grep -qi -- '--containers' "$POD_SH"; } || r+="--containers option missing; "
  fail 5 "T7b pod.sh — Pods + containers resource usage script" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom NODE 10 "🔧 Node lifecycle (kubeadm)"

# T8a — join command generated from the control plane (3 + 2)
d=NODE
JOIN="$BASE/join-command.txt"
if [ -f "$JOIN" ] \
   && grep -q 'kubeadm join' "$JOIN" \
   && grep -q ':6443' "$JOIN" \
   && grep -q -- '--token' "$JOIN" \
   && grep -q -- '--discovery-token-ca-cert-hash sha256:' "$JOIN"; then
  pass 3 "T8a join-command.txt — complete kubeadm join command (endpoint + token + CA hash)" $d
else
  r=""
  [ -f "$JOIN" ] || r+="join-command.txt missing; "
  { [ -f "$JOIN" ] && grep -q 'kubeadm join' "$JOIN"; } || r+="no 'kubeadm join'; "
  { [ -f "$JOIN" ] && grep -q ':6443' "$JOIN"; } || r+="API endpoint (:6443) missing; "
  { [ -f "$JOIN" ] && grep -q -- '--token' "$JOIN"; } || r+="--token missing; "
  { [ -f "$JOIN" ] && grep -q -- '--discovery-token-ca-cert-hash sha256:' "$JOIN"; } || r+="CA hash (--discovery-token-ca-cert-hash) missing; "
  fail 3 "T8a join-command.txt — complete kubeadm join command" $d "${r%; }"
fi

# token actually generated: the bootstrap-token-<id> Secret must exist (deterministic read)
tok=$( [ -f "$JOIN" ] && grep -oE '[a-z0-9]{6}\.[a-z0-9]{16}' "$JOIN" | head -1 )
tokid="${tok%%.*}"
if [ -n "$tok" ] && kubectl -n kube-system get secret "bootstrap-token-$tokid" >/dev/null 2>&1; then
  pass 2 "T8a token — the command's token actually exists in the cluster" $d
else
  fail 2 "T8a token — real token generated via kubeadm (bootstrap-token Secret present)" $d \
    "$( [ -n "$tok" ] && echo "token '$tok' not found (bootstrap-token-$tokid missing — expired? made up?)" || echo "no token in xxxxxx.xxxxxxxxxxxxxxxx format in the file" )"
fi

# T8b — worker upgrade runbook (3 + 2)
UPN="$BASE/upgrade-node.sh"
if [ -f "$UPN" ] && grep -Eqi 'kubeadm[[:space:]]+upgrade[[:space:]]+node' "$UPN"; then
  pass 3 "T8b upgrade-node.sh — uses 'kubeadm upgrade node' (worker variant, ≠ apply)" $d
else
  r=""
  [ -f "$UPN" ] || r+="upgrade-node.sh missing; "
  { [ -f "$UPN" ] && grep -Eqi 'kubeadm[[:space:]]+upgrade[[:space:]]+node' "$UPN"; } || r+="no 'kubeadm upgrade node' (a worker does not use 'upgrade apply'); "
  fail 3 "T8b upgrade-node.sh — worker upgrade procedure" $d "${r%; }"
fi

if [ -f "$UPN" ] && grep -Eqi 'restart[[:space:]]+kubelet|kubelet[[:space:]]+restart' "$UPN" \
   && grep -Eqi 'apt-mark|apt-get[[:space:]]+install|kubelet=' "$UPN"; then
  pass 2 "T8b upgrade-node.sh — updates the kubelet package then restarts the service" $d
else
  r=""
  { [ -f "$UPN" ] && grep -Eqi 'apt-mark|apt-get[[:space:]]+install|kubelet=' "$UPN"; } || r+="no kubelet package update (apt-mark/apt-get); "
  { [ -f "$UPN" ] && grep -Eqi 'restart[[:space:]]+kubelet|kubelet[[:space:]]+restart' "$UPN"; } || r+="no kubelet restart (systemctl restart kubelet); "
  fail 2 "T8b upgrade-node.sh — kubelet update + restart" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom APIACC 10 "🔐 Kubernetes API from a Pod"

# T9a — Pod using the ServiceAccount (5)
d=APIACC
img=$(kubectl -n project-audit get pod secret-probe -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
sa=$(kubectl -n project-audit get pod secret-probe -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
phase=$(kubectl -n project-audit get pod secret-probe -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$img" = "nginx:1-alpine" ] && [ "$sa" = "probe-sa" ] && [ "$phase" = "Running" ]; then
  pass 5 "T9a Pod secret-probe — nginx:1-alpine, ServiceAccount probe-sa, Running" $d
else
  r=""
  [ "$img" = "nginx:1-alpine" ] || r+="image=${img:-missing}(≠nginx:1-alpine); "
  [ "$sa" = "probe-sa" ]        || r+="serviceAccountName=${sa:-default}(≠probe-sa); "
  [ "$phase" = "Running" ]      || r+="phase=${phase:-missing}; "
  fail 5 "T9a Pod secret-probe — nginx:1-alpine using the SA probe-sa" $d "${r%; }"
fi

# T9b — API request result (SecretList JSON) written to the file (3 + 2)
RES="$BASE/secrets.json"
if [ -f "$RES" ] && grep -q '"kind"' "$RES" && grep -q 'SecretList' "$RES"; then
  pass 3 "T9b secrets.json — API response: list of Secrets (kind SecretList)" $d
else
  r=""
  [ -f "$RES" ] || r+="secrets.json missing; "
  { [ -f "$RES" ] && grep -q 'SecretList' "$RES"; } || r+="not a SecretList API response; "
  fail 3 "T9b secrets.json — API JSON response (SecretList)" $d "${r%; }"
fi

if [ -f "$RES" ] && grep -q 'audit-key' "$RES"; then
  pass 2 "T9b secrets.json — indeed contains the namespace's audit-key Secret" $d
else
  fail 2 "T9b secrets.json — the 'audit-key' Secret must appear in the response" $d \
    "$( [ -f "$RES" ] && echo "audit-key not found (wrong namespace? insufficient SA permissions?)" || echo "secrets.json missing" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SCHED 10 "🛰️  DaemonSet & scheduling"

# T10 — DaemonSet on all nodes (4 image/labels + 3 requests + 3 scheduled everywhere)
d=SCHED
nnodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
ds_img=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
ds_lid=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.metadata.labels.id}' 2>/dev/null)
ds_luuid=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.metadata.labels.uuid}' 2>/dev/null)
if [ "$ds_img" = "httpd:2-alpine" ] && [ "$ds_lid" = "log-harvester" ] && [ "$ds_luuid" = "7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64" ]; then
  pass 4 "T10a DaemonSet log-harvester — httpd:2-alpine + labels id/uuid" $d
else
  r=""
  [ "$ds_img" = "httpd:2-alpine" ] || r+="image=${ds_img:-missing}(≠httpd:2-alpine); "
  [ "$ds_lid" = "log-harvester" ] || r+="label id=${ds_lid:-missing}; "
  [ "$ds_luuid" = "7c1f9a2e-4d6b-4a11-8f3c-2b9e0d5a7c64" ] || r+="label uuid incorrect; "
  fail 4 "T10a DaemonSet log-harvester — image + labels id/uuid" $d "${r%; }"
fi

ds_cpu=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
ds_mem=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null)
if [ "$ds_cpu" = "15m" ] && [ "$ds_mem" = "20Mi" ]; then
  pass 3 "T10b requests — cpu 15m + memory 20Mi" $d
else
  fail 3 "T10b requests — cpu 15m + memory 20Mi" $d "cpu=${ds_cpu:-missing}, mem=${ds_mem:-missing}"
fi

ds_des=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
ds_rdy=$(kubectl -n project-batch get ds log-harvester -o jsonpath='{.status.numberReady}' 2>/dev/null)
if [ -n "$ds_des" ] && [ "$ds_des" = "$nnodes" ] && [ "${ds_rdy:-0}" = "$nnodes" ]; then
  pass 3 "T10c scheduling — one Pod Ready on all $nnodes nodes (control-plane tolerated)" $d
else
  fail 3 "T10c scheduling — one Pod Ready on all nodes (including control-plane)" $d \
    "desired=${ds_des:-0}/$nnodes, ready=${ds_rdy:-0}/$nnodes (control-plane toleration missing?)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom AFFIN 10 "🧢 Affinity & multi-container"

# T11 — Deployment 2 containers + podAntiAffinity (4 + 3 + 3)
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
  pass 4 "T11a Deployment edge-cache — 3 replicas, label id=edge-node, containers main+sidecar" $d
else
  r=""
  [ "$rep" = "3" ] || r+="replicas=${rep:-missing}(≠3); "
  [ "$dlid" = "edge-node" ] || r+="label id=${dlid:-missing}; "
  { [ "$c0n" = "main" ] && [ "$c0i" = "nginx:1-alpine" ]; } || r+="container1 main/nginx:1-alpine KO (${c0n:-?}/${c0i:-?}); "
  { [ "$c1n" = "sidecar" ] && [ "$c1i" = "registry.k8s.io/pause:3.10" ]; } || r+="container2 sidecar/pause:3.10 KO (${c1n:-?}/${c1i:-?}); "
  fail 4 "T11a Deployment edge-cache — 3 replicas + label + 2 containers" $d "${r%; }"
fi

tk=$(kubectl -n project-batch get deploy edge-cache -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey}' 2>/dev/null)
if [ "$tk" = "kubernetes.io/hostname" ]; then
  pass 3 "T11b anti-affinity — podAntiAffinity required on topologyKey kubernetes.io/hostname" $d
else
  fail 3 "T11b anti-affinity — podAntiAffinity (topologyKey kubernetes.io/hostname)" $d "topologyKey=${tk:-missing}"
fi

run=$(kubectl -n project-batch get pods -l id=edge-node --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
pend=$(kubectl -n project-batch get pods -l id=edge-node --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$run" = "2" ] && [ "${pend:-0}" -ge 1 ]; then
  pass 3 "T11c spread — 2 Pods Running (1/node) + 1 Pending (3rd unschedulable)" $d
else
  fail 3 "T11c spread — 2 Running (1 per node) + 1 Pending" $d "Running=${run:-0} (expected 2), Pending=${pend:-0} (expected ≥1)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom CERTS 10 "🔐 Cluster certificates"

# T13 — apiserver expiration (5) + renew command (5)
d=CERTS
EXP="$BASE/apiserver-expiration"
# Ground truth: apiserver certificate expiration year (openssl on the real cert)
exp_year=$(sudo -n openssl x509 -noout -enddate -in /etc/kubernetes/pki/apiserver.crt 2>/dev/null | grep -oE '20[0-9]{2}')
if [ -f "$EXP" ] && [ -s "$EXP" ] && [ -n "$exp_year" ] && grep -q "$exp_year" "$EXP"; then
  pass 5 "T13a apiserver-expiration — kube-apiserver cert expiration date ($exp_year)" $d
else
  r=""
  [ -f "$EXP" ] || r+="apiserver-expiration missing; "
  { [ -f "$EXP" ] && [ -s "$EXP" ]; } || r+="empty file; "
  { [ -f "$EXP" ] && grep -q "${exp_year:-__}" "$EXP"; } || r+="does not contain the expected expiration year ($exp_year); "
  fail 5 "T13a apiserver-expiration — kube-apiserver cert expiration date" $d "${r%; }"
fi

RNW="$BASE/renew-apiserver.sh"
if [ -f "$RNW" ] && grep -Eq 'kubeadm[[:space:]]+certs[[:space:]]+renew[[:space:]]+apiserver' "$RNW"; then
  pass 5 "T13b renew-apiserver.sh — 'kubeadm certs renew apiserver' command" $d
else
  r=""
  [ -f "$RNW" ] || r+="renew-apiserver.sh missing; "
  { [ -f "$RNW" ] && grep -Eq 'kubeadm[[:space:]]+certs[[:space:]]+renew[[:space:]]+apiserver' "$RNW"; } || r+="no 'kubeadm certs renew apiserver'; "
  fail 5 "T13b renew-apiserver.sh — kubeadm renewal command" $d "${r%; }"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom NETEG 10 "🛡️  Networking — NetworkPolicy egress"

# T14 — egress backend → cache-a:6379 / cache-b:5432 (spec 2/2/2 + enforcement runtime 2/2)
d=NETEG
np_pod=$(kubectl -n project-mesh get netpol np-egress -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null)
np_types=$(kubectl -n project-mesh get netpol np-egress -o jsonpath='{.spec.policyTypes[*]}' 2>/dev/null)
if [ "$np_pod" = "backend" ] && printf '%s' "$np_types" | grep -qw Egress; then
  pass 2 "T14a np-egress — selects app=backend, policyTypes Egress" $d
else
  r=""
  [ "$np_pod" = "backend" ] || r+="podSelector app=${np_pod:-missing}(≠backend); "
  printf '%s' "$np_types" | grep -qw Egress || r+="policyTypes without Egress (=${np_types:-missing}); "
  fail 2 "T14a np-egress — podSelector app=backend + policyTypes Egress" $d "${r%; }"
fi

# (target:port) pairs per egress rule — a correct rule pairs a single target with its port
pairs=$(kubectl -n project-mesh get netpol np-egress -o jsonpath='{range .spec.egress[*]}{.to[0].podSelector.matchLabels.app}:{.ports[0].port}{"\n"}{end}' 2>/dev/null)
if printf '%s' "$pairs" | grep -qx 'cache-a:6379'; then
  pass 2 "T14b egress — allows app=cache-a on port 6379" $d
else
  fail 2 "T14b egress — app=cache-a on port 6379" $d "rules (target:port) = $(printf '%s' "$pairs" | tr '\n' ' ')"
fi
if printf '%s' "$pairs" | grep -qx 'cache-b:5432'; then
  pass 2 "T14c egress — allows app=cache-b on port 5432" $d
else
  fail 2 "T14c egress — app=cache-b on port 5432" $d "rules (target:port) = $(printf '%s' "$pairs" | tr '\n' ' ')"
fi

# T14d/e — runtime enforcement (connection by IP from backend, without relying on DNS).
#          cache-a/cache-b/vault are agnhost listeners seeded by setup.sh.
NSM=project-mesh
be=$(kubectl -n $NSM get pod -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
ca_ip=$(kubectl -n $NSM get pod -l app=cache-a -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
vault_ip=$(kubectl -n $NSM get pod -l app=vault -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
if [ -n "$be" ] && [ -n "$ca_ip" ] && kubectl -n $NSM exec "$be" -- /agnhost connect "$ca_ip:6379" --timeout=3s >/dev/null 2>&1; then
  pass 2 "T14d enforcement — backend does reach cache-a:6379 (allowed)" $d
else
  fail 2 "T14d enforcement — backend must be able to reach cache-a:6379" $d \
    "$( [ -z "$be" ] && echo "backend pod missing" || { [ -z "$ca_ip" ] && echo "cache-a IP not found" || echo "connection refused/timeout — the egress rule cache-a:6379 is missing or the labels are incorrect"; } )"
fi
if [ -n "$be" ] && [ -n "$vault_ip" ] && ! kubectl -n $NSM exec "$be" -- /agnhost connect "$vault_ip:9999" --timeout=3s >/dev/null 2>&1; then
  pass 2 "T14e enforcement — backend does NOT reach vault:9999 (blocked)" $d
else
  fail 2 "T14e enforcement — egress to vault:9999 must be blocked" $d \
    "$( [ -z "$be" ] && echo "backend pod missing" || { [ -z "$vault_ip" ] && echo "vault IP not found" || echo "vault:9999 is reachable — egress too permissive (policyTypes Egress missing or catch-all rule)"; } )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom CRICTL 10 "🔎  Debug — container runtime (crictl)"

# T16 — container-info.txt (ID + runtimeType) + container.log (4 ID / 3 runtime / 3 log)
d=CRICTL
info="$BASE/container-info.txt"
logf="$BASE/container.log"
if [ -f "$info" ] && grep -qiE '[0-9a-f]{12,}' "$info"; then
  pass 4 "T16a container-info.txt — contains a container ID (hexadecimal ≥12)" $d
else
  fail 4 "T16a container-info.txt — hexadecimal container ID" $d "file missing or without hex ID (≥ 12 chars)"
fi
if [ -f "$info" ] && grep -qiE 'runc|runtimeType' "$info"; then
  pass 3 "T16b container-info.txt — runtime type (runc / runtimeType)" $d
else
  fail 3 "T16b container-info.txt — runtime type (info.runtimeType)" $d "the runtimeType field (e.g. io.containerd.runc.v2) is missing"
fi
if [ -f "$logf" ]; then
  pass 3 "T16c container.log — container logs captured" $d
else
  fail 3 "T16c container.log — log file" $d "file /opt/exam-03/container.log missing"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom GWAPI 10 "🚪  Gateway API — HTTP routing"

# T12 — HTTPRoute route-splitter (4 parentRefs / 3 paths / 3 header)
d=GWAPI
if kubectl -n project-edge get httproute route-splitter >/dev/null 2>&1; then
  prefs=$(kubectl -n project-edge get httproute route-splitter -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$prefs" | grep -qw edge-gw; then
    pass 3 "T12a route-splitter — attached to the Gateway edge-gw (parentRefs)" $d
  else
    fail 3 "T12a route-splitter — parentRefs to edge-gw" $d "parentRefs = ${prefs:-empty}"
  fi

  paths=$(kubectl -n project-edge get httproute route-splitter -o jsonpath='{range .spec.rules[*].matches[*]}{.path.value}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$paths" | grep -qx '/web' && printf '%s' "$paths" | grep -qx '/svc'; then
    pass 3 "T12b route-splitter — prefix routes /web and /svc" $d
  else
    fail 3 "T12b route-splitter — prefixes /web and /svc" $d "paths found = $(printf '%s' "$paths" | tr '\n' ' ')"
  fi

  # (path|header) pairs per match: a match combining path AND header applies a logical AND
  ph=$(kubectl -n project-edge get httproute route-splitter -o jsonpath='{range .spec.rules[*].matches[*]}{.path.value}|{.headers[0].name}={.headers[0].value}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$ph" | grep -qix '/shop|X-Tier=premium'; then
    pass 2 "T12c route-splitter — /shop + X-Tier: premium header in the same match (logical AND)" $d
  else
    fail 2 "T12c route-splitter — /shop conditioned by X-Tier: premium (same match)" $d "matches (path|header) = $(printf '%s' "$ph" | tr '\n' ' ')"
  fi
  if printf '%s' "$ph" | grep -qx '/shop|='; then
    pass 2 "T12d route-splitter — catch-all /shop (no header) to the default backend" $d
  else
    fail 2 "T12d route-splitter — /shop catch-all (otherwise)" $d "no /shop match without header (fallback) found"
  fi
else
  fail 3 "T12a route-splitter — attached to the Gateway edge-gw (parentRefs)" $d "HTTPRoute route-splitter missing from project-edge"
  fail 3 "T12b route-splitter — prefixes /web and /svc" $d "HTTPRoute missing"
  fail 2 "T12c route-splitter — /shop + X-Tier: premium (same match)" $d "HTTPRoute missing"
  fail 2 "T12d route-splitter — /shop catch-all" $d "HTTPRoute missing"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom COREDNS 10 "🧭  CoreDNS — custom domain"

# T15 — backup + Corefile with cka.local (4 backup / 3 mention / 3 kubernetes plugin)
d=COREDNS
bk="$BASE/coredns_original.yaml"
if [ -f "$bk" ] && grep -qi 'kind.*configmap' "$bk" && grep -q 'Corefile' "$bk"; then
  pass 4 "T15a coredns_original.yaml — backup of the coredns ConfigMap" $d
else
  fail 4 "T15a coredns_original.yaml — valid backup of the coredns ConfigMap" $d "file missing or not the coredns ConfigMap (kind ConfigMap + Corefile key)"
fi
cf=$(kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' 2>/dev/null)
if printf '%s' "$cf" | grep -q 'cka\.local'; then
  pass 3 "T15b Corefile — the cka.local domain is declared" $d
else
  fail 3 "T15b Corefile — cka.local domain" $d "the coredns ConfigMap's Corefile does not contain cka.local"
fi
if printf '%s' "$cf" | grep -qE 'kubernetes.*cka\.local'; then
  pass 3 "T15c Corefile — cka.local resolved by the kubernetes plugin" $d
else
  fail 3 "T15c Corefile — cka.local on the kubernetes plugin line" $d "cka.local must be added to the 'kubernetes' plugin zones (e.g. kubernetes cluster.local cka.local …)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom ETCD 9 "🗄️  etcd — introspection"

# T17 — etcd-info.txt: private key / cert expiration / client-cert-auth (3/3/3)
d=ETCD
ei="$BASE/etcd-info.txt"
if [ -f "$ei" ] && grep -qE 'server\.key|etcd/.*\.key' "$ei"; then
  pass 3 "T17a etcd-info.txt — location of the server private key (server.key)" $d
else
  fail 3 "T17a etcd-info.txt — path of etcd's server private key" $d "the path of server.key (pki/etcd/server.key) is missing from the file"
fi
if [ -f "$ei" ] && grep -qE '20[0-9]{2}' "$ei"; then
  pass 3 "T17b etcd-info.txt — server certificate expiration date" $d
else
  fail 3 "T17b etcd-info.txt — etcd server cert expiration date" $d "no expiration year (e.g. 2027) found in the file"
fi
if [ -f "$ei" ] && grep -qiE 'client.?cert.?auth|auth.*client' "$ei" && grep -qiE '\btrue\b|\byes\b|\boui\b|enabled|activ' "$ei"; then
  pass 3 "T17c etcd-info.txt — client certificate authentication enabled" $d
else
  fail 3 "T17c etcd-info.txt — state of client certificate authentication" $d "the client-cert-auth mention and its value (enabled/true/yes) is missing"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom KPROXY 8 "🔀  kube-proxy & iptables"

# T18 — Pod+Service + capture of iptables rules (4 objects / 4 capture)
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
  fail 4 "T18a Pod p-proxy + Service proxy-svc (ClusterIP 3100→80)" $d "the Pod p-proxy is not Running or proxy-svc does not map 3100→80 as ClusterIP"
fi
ipf="$BASE/iptables.txt"
cip="$(kubectl -n project-proxy get svc proxy-svc -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
if [ -f "$ipf" ] && grep -qiE 'KUBE-(SVC|SEP|SERVICES)' "$ipf" && { grep -qi 'proxy-svc' "$ipf" || { [ -n "$cip" ] && grep -q "$cip" "$ipf"; }; }; then
  pass 4 "T18b iptables.txt — Service's kube-proxy rules captured" $d
else
  fail 4 "T18b iptables.txt — Service proxy-svc iptables rules (nat)" $d "the file contains neither the KUBE-SVC chains nor the Service's clusterIP/name"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SVCCIDR 10 "🌐  Service CIDR (multi-range)"

# T19 — additive ServiceCIDR + Service in the new range (4 CIDR / 4 IP / 2 base)
d=SVCCIDR
sc_cidrs="$(kubectl get servicecidr extra-range -o jsonpath='{.spec.cidrs}' 2>/dev/null)"
if echo "$sc_cidrs" | grep -q '11.96.0.0/12'; then
  pass 4 "T19a ServiceCIDR extra-range covers 11.96.0.0/12" $d
else
  fail 4 "T19a ServiceCIDR extra-range (11.96.0.0/12)" $d "the ServiceCIDR extra-range object is missing or does not cover 11.96.0.0/12"
fi
cip2="$(kubectl -n project-range get svc range-svc2 -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
if echo "$cip2" | grep -qE '^11\.(9[6-9]|10[0-9]|11[01])\.[0-9]+\.[0-9]+$'; then
  pass 4 "T19b range-svc2 — clusterIP in the new range 11.96.0.0/12" $d
else
  fail 4 "T19b range-svc2 — clusterIP from 11.96.0.0/12" $d "range-svc2 has no clusterIP within 11.96.0.0/12"
fi
rp_ok=0; rs_ok=0
[ "$(kubectl -n project-range get pod range-probe -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && rp_ok=1
[ "$(kubectl -n project-range get svc range-svc -o jsonpath='{.spec.type}' 2>/dev/null)" = "ClusterIP" ] && rs_ok=1
if [ "$rp_ok" = 1 ] && [ "$rs_ok" = 1 ]; then
  pass 2 "T19c Pod range-probe (Running) + Service range-svc (ClusterIP)" $d
else
  fail 2 "T19c Pod range-probe + Service range-svc (ClusterIP)" $d "the Pod range-probe is not Running or range-svc is not a ClusterIP"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
TOTAL=0; GOT=0
printf "\n────────────────────────────────────────────────────────\n"
printf "Subtotals per domain:\n"
declare -A DOM_LABEL=( [KUBECFG]="Cluster Architecture & kubeconfig" [PKG]="Packaging & Helm" [WL]="Workloads & Scheduling" [AUTO]="HPA & Kustomize" [STO]="Storage" [OBS]="Observability" [NODE]="Node lifecycle" [APIACC]="API from a Pod" [SCHED]="DaemonSet & tolerations" [AFFIN]="Affinity & multi-container" [GWAPI]="Gateway API" [CERTS]="Cluster certificates" [NETEG]="NetworkPolicy egress" [COREDNS]="CoreDNS" [CRICTL]="Debug crictl" [ETCD]="etcd — introspection" [KPROXY]="kube-proxy & iptables" [SVCCIDR]="Service CIDR (multi-range)" )
for k in KUBECFG PKG WL AUTO STO OBS NODE APIACC SCHED AFFIN GWAPI CERTS NETEG COREDNS CRICTL ETCD KPROXY SVCCIDR; do
  [ -n "${DOM_MAX[$k]:-}" ] || continue
  printf "  %-34s %2d / %d\n" "${DOM_LABEL[$k]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
  TOTAL=$((TOTAL + DOM_MAX[$k])); GOT=$((GOT + ${DOM_GOT[$k]:-0}))
done
printf "────────────────────────────────────────────────────────\n"
printf "TOTAL SCORE : %d / %d\n" "$GOT" "$TOTAL"
if [ "$TOTAL" -gt 0 ] && [ $((GOT*100/TOTAL)) -ge 66 ]; then
  printf "\033[32m🎉 PASSED (≥ 66%%)\033[0m\n"
else
  printf "\033[31mFAILED (< 66%%)\033[0m\n"
fi
printf "────────────────────────────────────────────────────────\n"
