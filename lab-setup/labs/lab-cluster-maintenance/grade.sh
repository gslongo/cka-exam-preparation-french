#!/usr/bin/env bash
# grade.sh — auto-grader for the "Cluster Maintenance, etcd & Security" lab.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-cluster-maintenance/grade.sh"
#
# Read-only: it changes NOTHING. Prints PASS/FAIL per task (with the observed symptom,
# never the solution), a per-section subtotal and a score out of 100 (target ≥ 75%).
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }
jp()   { kubectl "$@" 2>/dev/null; }
etcdctl_pod() { kubectl -n kube-system exec etcd-cp1 -- "$@" 2>/dev/null; }

# ══════════════════════════════════════════════════════════════════════════════
dom ETCD 24 "🗄️  etcd Backup & Restore"

# T1 — etcd snapshot saved and valid (12)
d=ETCD
if sudo test -f /var/lib/etcd/etcd-backup.db && etcdctl_pod etcdutl snapshot status /var/lib/etcd/etcd-backup.db >/dev/null 2>&1; then
  pass 12 "T1 etcd backup — /var/lib/etcd/etcd-backup.db is a valid snapshot" $d
else
  ex=$(sudo test -f /var/lib/etcd/etcd-backup.db && echo yes || echo no)
  fail 12 "T1 etcd backup — save a valid etcd snapshot to /var/lib/etcd/etcd-backup.db" $d "file present=${ex}, etcdutl snapshot status failed or file missing"
fi

# T2 — snapshot restored into an alternate data-dir (12)
d=ETCD
if sudo test -d /var/lib/etcd/restore/member/snap && sudo test -d /var/lib/etcd/restore/member/wal; then
  pass 12 "T2 etcd restore — snapshot restored into /var/lib/etcd/restore" $d
else
  fail 12 "T2 etcd restore — restore the snapshot into a new data-dir /var/lib/etcd/restore" $d "expected /var/lib/etcd/restore/member/{snap,wal} to exist"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom CERTS 22 "🔐 Certificates & CSR"

# T3 — CSR 'applicant' approved and issued (10)
# K8s garbage-collects APPROVED CSRs after ~1 h → the exported certificate file
# is accepted as durable evidence when the CSR object is already gone.
d=CERTS
appr=$(jp get csr applicant -o jsonpath='{.status.conditions[?(@.type=="Approved")].status}')
cert=$(jp get csr applicant -o jsonpath='{.status.certificate}')
file_ok=no
if sudo test -f /opt/cka/applicant.crt \
   && sudo openssl verify -CAfile /etc/kubernetes/pki/ca.crt /opt/cka/applicant.crt >/dev/null 2>&1 \
   && sudo openssl x509 -in /opt/cka/applicant.crt -noout -subject 2>/dev/null | grep -q 'CN *= *applicant'; then
  file_ok=yes
fi
if { [ "$appr" = "True" ] && [ -n "$cert" ]; } || [ "$file_ok" = "yes" ]; then
  pass 10 "T3 CSR — 'applicant' approved and certificate issued" $d
else
  fail 10 "T3 CSR — approve the pending CSR 'applicant' and save the issued cert to /opt/cka/applicant.crt" $d "Approved=${appr:-∅}, certificate=$([ -n "$cert" ] && echo issued || echo empty), /opt/cka/applicant.crt=${file_ok} (note: approved CSRs are GC'd after ~1 h)"
fi

# T4 — kube-apiserver certificate expiration written to the report file (12)
d=CERTS
exp=$(sudo kubeadm certs check-expiration 2>/dev/null | awk '/^apiserver /{print $2, $3, $4; exit}')
if [ -f /opt/cka/apiserver-expiration.txt ] && [ -n "$exp" ] && grep -qF "$exp" /opt/cka/apiserver-expiration.txt 2>/dev/null; then
  pass 12 "T4 cert expiry — apiserver expiration date reported correctly" $d
else
  got=$( [ -f /opt/cka/apiserver-expiration.txt ] && tr -d '\n' < /opt/cka/apiserver-expiration.txt | cut -c1-40 || echo "file missing")
  fail 12 "T4 cert expiry — write the kube-apiserver cert expiration date to /opt/cka/apiserver-expiration.txt" $d "expected to contain '${exp:-?}', got: ${got}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom RBAC 34 "👤 RBAC & Authorization"

# T5 — cluster-wide read-only ClusterRole bound to group 'viewers' (12)
d=RBAC
cl=$(jp auth can-i list pods --all-namespaces --as=tester --as-group=viewers)
cd_=$(jp auth can-i delete pods --all-namespaces --as=tester --as-group=viewers)
if [ "$cl" = "yes" ] && [ "$cd_" = "no" ]; then
  pass 12 "T5 RBAC — group 'viewers' can list pods cluster-wide but not delete" $d
else
  r=""
  [ "$cl" = "yes" ] || r+="cannot 'list' pods cluster-wide; "
  [ "$cd_" = "no" ] || r+="can 'delete' pods (too permissive); "
  fail 12 "T5 RBAC — bind ClusterRole 'pod-viewer' (get/list/watch pods) to group 'viewers'" $d "${r%; }"
fi

# T6 — namespaced Role for user 'auditor' in ns 'finance' (12)
d=RBAC
cf=$(jp auth can-i create configmaps -n finance --as=auditor)
cx=$(jp auth can-i create configmaps -n default --as=auditor)
if [ "$cf" = "yes" ] && [ "$cx" = "no" ]; then
  pass 12 "T6 RBAC — user 'auditor' can manage configmaps in 'finance' only" $d
else
  r=""
  [ "$cf" = "yes" ] || r+="cannot create configmaps in 'finance'; "
  [ "$cx" = "no" ]  || r+="can create configmaps outside 'finance' (Role too wide / ClusterRoleBinding?); "
  fail 12 "T6 RBAC — grant user 'auditor' configmap management in ns 'finance' (namespaced)" $d "${r%; }"
fi

# T7 — ServiceAccount token exported (10)
# JWT payload is decoded offline: the token stays verifiable even after it expires.
d=RBAC
sa9=$(jp -n finance get sa robot -o name)
tok_ok=no
if sudo test -f /opt/cka/robot-token.txt; then
  tok=$(sudo tr -d ' \r\n' < /opt/cka/robot-token.txt)
  payload=$(printf '%s' "$tok" | cut -d. -f2 | tr '_-' '/+')
  case $(( ${#payload} % 4 )) in 2) payload="$payload==";; 3) payload="$payload=";; esac
  if printf '%s' "$payload" | base64 -d 2>/dev/null | grep -q '"sub":"system:serviceaccount:finance:robot"'; then
    tok_ok=yes
  fi
fi
if [ -n "$sa9" ] && [ "$tok_ok" = "yes" ]; then
  pass 10 "T7 token — SA finance/robot exists, valid token exported" $d
else
  fail 10 "T7 token — create SA 'robot' in ns finance and write its token to /opt/cka/robot-token.txt" $d "SA=$([ -n "$sa9" ] && echo present || echo missing), token file=$(sudo test -f /opt/cka/robot-token.txt && echo "present but sub≠finance/robot or not a JWT" || echo missing)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom NODES 20 "🖥️  Nodes & Static Pods"

# T8 — node w1 drained for maintenance (10)
d=NODES
u1=$(jp get node w1 -o jsonpath='{.spec.unschedulable}')
onw1=$(jp -n legacy get pods --field-selector spec.nodeName=w1 --no-headers 2>/dev/null | grep -c .)
if [ "$u1" = "true" ] && [ "${onw1:-0}" -eq 0 ]; then
  pass 10 "T8 drain — w1 cordoned and 'legacy-app' evicted" $d
else
  fail 10 "T8 drain — drain node w1 (cordon + evict workloads) for maintenance" $d "w1 unschedulable=${u1:-false}, legacy-app pods still on w1=${onw1:-?}"
fi

# T9 — static pod on cp1 (10)
d=NODES
# -n default: do not depend on the user's current kubeconfig context namespace
phase=$(jp get pod web-static-cp1 -n default -o jsonpath='{.status.phase}')
owner=$(jp get pod web-static-cp1 -n default -o jsonpath='{.metadata.ownerReferences[0].kind}')
img=$(jp get pod web-static-cp1 -n default -o jsonpath='{.spec.containers[0].image}')
if [ "$phase" = "Running" ] && [ "$owner" = "Node" ] && printf '%s' "$img" | grep -q 'nginx:1.29-alpine'; then
  pass 10 "T9 static pod — 'web-static-cp1' Running (managed by kubelet)" $d
else
  fail 10 "T9 static pod — create a static pod 'web-static' on cp1 (nginx:1.29-alpine)" $d "phase=${phase:-absent}, owner=${owner:-?}, image=${img:-∅} (expected Running/Node/nginx:1.29-alpine)"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "────────────────────────────────────────────────────────"
printf "\033[1mSubtotal per section:\033[0m\n"
order=(ETCD CERTS RBAC NODES)
names=( "etcd Backup & Restore" "Certificates & CSR" "RBAC & Authorization" "Nodes & Static Pods" )
for i in "${!order[@]}"; do
  k=${order[$i]}
  printf "  %-30s %2d / %2d\n" "${names[$i]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
done
echo "────────────────────────────────────────────────────────"
printf "\033[1mTOTAL SCORE : %d / 100\033[0m\n" "$SCORE"
if [ "$SCORE" -ge 75 ]; then
  printf "\033[32m🎉 TARGET REACHED (≥ 75%%)\033[0m\n"
else
  printf "\033[31mKEEP PRACTISING (< 75%%) — %d pts short\033[0m\n" $((75-SCORE))
fi
echo "────────────────────────────────────────────────────────"
