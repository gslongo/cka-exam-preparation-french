#!/usr/bin/env bash
# grade.sh — auto-grader for the "Cross-cutting Troubleshooting" lab.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-troubleshooting/grade.sh"
#
# Read-only: it changes NOTHING. Prints PASS/FAIL per task (with the observed symptom,
# never the solution), a per-domain subtotal and a score out of 100 (target ≥ 75%).
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }
jp()   { kubectl "$@" 2>/dev/null; }

# ══════════════════════════════════════════════════════════════════════════════
dom ARCH 25 "🏛️  Cluster Architecture & Nodes"

# A1 — RBAC fixed (8)
d=ARCH
can_list=$(jp auth can-i list pods --as=system:serviceaccount:ts-arch:deploy-bot -n ts-arch)
can_del=$(jp auth can-i delete pods --as=system:serviceaccount:ts-arch:deploy-bot -n ts-arch)
if [ "$can_list" = "yes" ] && [ "$can_del" = "no" ]; then
  pass 7 "A1 RBAC — deploy-bot can list but not delete pods" $d
else
  r=""
  [ "$can_list" = "yes" ] || r+="cannot 'list' pods; "
  [ "$can_del" = "no" ]   || r+="can 'delete' pods (too permissive); "
  fail 7 "A1 RBAC — deploy-bot must be able to 'list' but not 'delete' pods" $d "${r%; }"
fi

# A2 — static pod fixed on cp1 (8)
d=ARCH
phase=$(jp get pod ts-static-cp1 -n default -o jsonpath='{.status.phase}')
img=$(jp get pod ts-static-cp1 -n default -o jsonpath='{.spec.containers[0].image}')
owner=$(jp get pod ts-static-cp1 -n default -o jsonpath='{.metadata.ownerReferences[0].kind}')
# Any pullable image is accepted (Running proves it) — the statement only asks for "a valid image".
if [ "$phase" = "Running" ] && [ "$owner" = "Node" ]; then
  pass 7 "A2 static pod — ts-static-cp1 Running (image fixed)" $d
else fail 7 "A2 static pod — fix the static manifest on cp1 (pod Running)" $d "phase=${phase:-absent}, image=${img:-∅}, owner=${owner:-?} (expected Running, owner Node)"; fi

# A3 — node w1 back in service, billing scheduled (8)
d=ARCH
avail=$(jp -n ts-nodes get deploy billing -o jsonpath='{.status.availableReplicas}')
if [ "${avail:-0}" -ge 1 ]; then
  pass 7 "A3 node — w1 fixed (cordon + taint), billing available" $d
else
  u1=$(jp get node w1 -o jsonpath='{.spec.unschedulable}')
  t1=$(jp get node w1 -o jsonpath='{.spec.taints[?(@.key=="maintenance")].effect}')
  fail 7 "A3 node — bring w1 back in service so 'billing' starts" $d "billing available=${avail:-0} ; w1 unschedulable=${u1:-false}, taint maintenance=${t1:-∅}"
fi

# A4 — Terminating object cleared (4)
d=ARCH
if jp -n ts-arch get cm stuck-cm >/dev/null 2>&1; then
  dt=$(jp -n ts-arch get cm stuck-cm -o jsonpath='{.metadata.deletionTimestamp}')
  fail 4 "A4 finalizer — the ConfigMap stuck-cm must be actually deleted" $d "stuck-cm still present (deletionTimestamp=${dt:-∅} → finalizer not removed)"
else
  pass 4 "A4 finalizer — stuck-cm cleared and deleted" $d
fi

# ══════════════════════════════════════════════════════════════════════════════
dom WORK 40 "📦 Workloads & Scheduling"

# W1 — image fixed (6)
d=WORK
img=$(jp -n ts-work get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
avail=$(jp -n ts-work get deploy web -o jsonpath='{.status.availableReplicas}')
# Any pullable image is accepted (availableReplicas proves it) — the statement only asks for "a valid image".
if [ "${avail:-0}" -ge 1 ]; then
  pass 5 "W1 image — deploy web fixed and available" $d
else fail 5 "W1 image — fix the image of 'web' (pods Running)" $d "image=${img:-∅}, availableReplicas=${avail:-0}"; fi

# W2 — CrashLoop fixed (6)
# NB: a pod in CrashLoopBackOff still has .status.phase=Running → we grade the
# container's readiness (false in CrashLoop, true when it actually runs).
d=WORK
phase=$(jp -n ts-work get pod crasher -o jsonpath='{.status.phase}')
ready=$(jp -n ts-work get pod crasher -o jsonpath='{.status.containerStatuses[0].ready}')
if [ "$phase" = "Running" ] && [ "$ready" = "true" ]; then
  pass 5 "W2 CrashLoop — crasher runs (container Ready)" $d
else
  rc=$(jp -n ts-work get pod crasher -o jsonpath='{.status.containerStatuses[0].restartCount}')
  reason=$(jp -n ts-work get pod crasher -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}')
  fail 5 "W2 CrashLoop — 'crasher' must run stably (container Ready)" $d "phase=${phase:-absent}, ready=${ready:-?}, restartCount=${rc:-?}${reason:+, state=$reason}"
fi

# W3 — Secret key added (6)
d=WORK
phase=$(jp -n ts-work get pod checkout -o jsonpath='{.status.phase}')
val=$(jp -n ts-work exec checkout -- printenv DB_PASSWORD 2>/dev/null | tr -d '\r\n')
if [ "$phase" = "Running" ] && [ -n "$val" ]; then
  pass 6 "W3 Secret — checkout Running, DB_PASSWORD injected" $d
else fail 6 "W3 Secret — add the missing key so 'checkout' starts" $d "phase=${phase:-absent}, DB_PASSWORD runtime=${val:-∅}"; fi

# W4 — Pending (requests) fixed (5)
d=WORK
phase=$(jp -n ts-work get pod report -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass 5 "W4 Pending — report is Running" $d
else fail 5 "W4 Pending — 'report' must run (realistic requests)" $d "phase=${phase:-absent}"; fi

# W5 — Pending (nodeSelector) fixed (5)
d=WORK
phase=$(jp -n ts-work get pod analytics -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass 5 "W5 Pending — analytics is Running" $d
else
  sel=$(jp -n ts-work get pod analytics -o jsonpath='{.spec.nodeSelector.disktype}')
  fail 5 "W5 Pending — 'analytics' must be schedulable (nodeSelector)" $d "phase=${phase:-absent}, nodeSelector disktype=${sel:-∅} (no labeled node?)"
fi

# W6 — readiness fixed (4)
d=WORK
rr=$(jp -n ts-work get deploy frontend -o jsonpath='{.status.readyReplicas}')
if [ "${rr:-0}" -ge 1 ]; then
  pass 4 "W6 readiness — frontend has Ready replicas" $d
else fail 4 "W6 readiness — fix 'frontend' probe (readyReplicas ≥ 1)" $d "readyReplicas=${rr:-0}"; fi

# W7 — OOMKilled fixed: adequate memory limit (5)
d=WORK
p7=$(jp -n ts-work get pod cruncher -o jsonpath='{.status.phase}')
rdy7=$(jp -n ts-work get pod cruncher -o jsonpath='{.status.containerStatuses[0].ready}')
rc7=$(jp -n ts-work get pod cruncher -o jsonpath='{.status.containerStatuses[0].restartCount}')
lim7=$(jp -n ts-work get pod cruncher -o jsonpath='{.spec.containers[0].resources.limits.memory}')
if [ "$p7" = "Running" ] && [ "$rdy7" = "true" ] && [ "${rc7:-1}" = "0" ] && [ -n "$lim7" ]; then
  pass 5 "W7 OOMKilled — cruncher runs with an adequate memory limit (${lim7})" $d
else
  last7=$(jp -n ts-work get pod cruncher -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}')
  fail 5 "W7 OOMKilled — 'cruncher' must run with 0 restarts and keep a memory limit" $d "phase=${p7:-absent}, ready=${rdy7:-?}, restarts=${rc7:-?}${last7:+, lastState=$last7}, memory limit=${lim7:-none}"
fi

# W8 — securityContext fixed: nginx starts (5)
d=WORK
p8w=$(jp -n ts-work get pod locked-web -o jsonpath='{.status.phase}')
rdy8=$(jp -n ts-work get pod locked-web -o jsonpath='{.status.containerStatuses[0].ready}')
img8=$(jp -n ts-work get pod locked-web -o jsonpath='{.spec.containers[0].image}')
if [ "$p8w" = "Running" ] && [ "$rdy8" = "true" ] && [ "$img8" = "nginx:1.29-alpine" ]; then
  pass 5 "W8 securityContext — locked-web runs (image kept)" $d
else
  ru8=$(jp -n ts-work get pod locked-web -o jsonpath='{.spec.securityContext.runAsUser}')
  fail 5 "W8 securityContext — fix 'locked-web' so nginx starts (keep nginx:1.29-alpine)" $d "phase=${p8w:-absent}, ready=${rdy8:-?}, image=${img8:-∅}, runAsUser=${ru8:-unset}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom NET 23 "🌐 Services & Networking"

# N1 — endpoints restored (7)
d=NET
eps=$(jp -n ts-net get endpoints api-svc -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$eps" -ge 1 ]; then
  pass 6 "N1 endpoints — api-svc has ${eps} endpoint(s)" $d
else fail 6 "N1 endpoints — fix the api-svc selector" $d "api-svc has ${eps} endpoint (expected ≥ 1)"; fi

# N2 — targetPort fixed (7, live test)
d=NET
if jp -n ts-net exec shop-client -- wget -T 4 -qO- http://shop-svc >/dev/null 2>&1; then
  pass 6 "N2 targetPort — shop-client reaches shop-svc" $d
else fail 6 "N2 targetPort — fix shop-svc targetPort (traffic OK)" $d "wget shop-client → shop-svc fails (targetPort ≠ container port?)"; fi

# N3 — NetworkPolicy fixed (7, live test)
d=NET
if jp -n ts-netpol exec client -- wget -T 4 -qO- http://backend >/dev/null 2>&1; then
  pass 6 "N3 NetworkPolicy — client reaches backend" $d
else fail 6 "N3 NetworkPolicy — allow client → backend (traffic OK)" $d "wget client → backend blocked (default-deny not fixed?)"; fi

# N4 — DNS restored (5, live test)
d=NET
if jp -n ts-net exec dns-broken -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
  pass 5 "N4 DNS — dns-broken resolves cluster services" $d
else
  dp=$(jp -n ts-net get pod dns-broken -o jsonpath='{.spec.dnsPolicy}')
  fail 5 "N4 DNS — 'dns-broken' must resolve *.svc.cluster.local" $d "dnsPolicy=${dp:-∅} ; kubernetes.default resolution fails"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 12 "💾 Storage"

# S1 — PVC Bound (7)
d=STO
ph=$(jp -n ts-storage get pvc data -o jsonpath='{.status.phase}')
if [ "$ph" = "Bound" ]; then
  pass 6 "S1 PVC — 'data' is Bound" $d
else
  sc=$(jp -n ts-storage get pvc data -o jsonpath='{.spec.storageClassName}')
  fail 6 "S1 PVC — 'data' must bind to a PV (Bound)" $d "phase=${ph:-absent}, storageClassName=${sc:-∅} (no PV in this class?)"
fi

# S2 — Pod mounted on PVC (7)
d=STO
phase=$(jp -n ts-storage get pod app -o jsonpath='{.status.phase}')
if [ "$phase" = "Running" ]; then
  pass 6 "S2 missing PVC — 'app' is Running (PVC created)" $d
else
  claim=$(jp -n ts-storage get pod app -o jsonpath='{.spec.volumes[0].persistentVolumeClaim.claimName}')
  exists=$(jp -n ts-storage get pvc "${claim:-app-pvc}" -o jsonpath='{.status.phase}')
  fail 6 "S2 missing PVC — create the PVC referenced by 'app'" $d "phase=${phase:-absent}, PVC '${claim:-app-pvc}'=${exists:-absent}"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "────────────────────────────────────────────────────────"
printf "\033[1mSubtotals per domain:\033[0m\n"
order=(ARCH WORK NET STO)
names=( "Cluster Architecture & Nodes" "Workloads & Scheduling" "Services & Networking" "Storage" )
for i in "${!order[@]}"; do
  k=${order[$i]}
  printf "  %-32s %2d / %2d\n" "${names[$i]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
done
echo "────────────────────────────────────────────────────────"
printf "\033[1mTOTAL SCORE : %d / 100\033[0m\n" "$SCORE"
if [ "$SCORE" -ge 75 ]; then
  printf "\033[32m🎉 TARGET REACHED (≥ 75%%)\033[0m\n"
else
  printf "\033[31mKEEP PRACTISING (< 75%%) — %d pts short\033[0m\n" $((75-SCORE))
fi
echo "────────────────────────────────────────────────────────"
