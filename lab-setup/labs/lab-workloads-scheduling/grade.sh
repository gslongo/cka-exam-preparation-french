#!/usr/bin/env bash
# grade.sh — auto-grader for the "Workloads & Scheduling" lab.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-workloads-scheduling/grade.sh"
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

# ══════════════════════════════════════════════════════════════════════════════
dom WL 21 "📦 Deployments & Rollouts"

# T1 — Deployment 'frontend' scaled to 3 (6)
d=WL
rr=$(jp -n w-deploy get deploy frontend -o jsonpath='{.status.readyReplicas}')
if [ "${rr:-0}" = "3" ]; then
  pass 6 "T1 frontend — Deployment scaled to 3 ready replicas" $d
else
  fail 6 "T1 frontend — create Deployment 'frontend' (nginx:1.29-alpine) and scale to 3" $d "readyReplicas=${rr:-0} (expected 3)"
fi

# T2 — RollingUpdate strategy maxSurge=2 maxUnavailable=0 (6)
d=WL
st=$(jp -n w-deploy get deploy rollout-app -o jsonpath='{.spec.strategy.type}')
ms=$(jp -n w-deploy get deploy rollout-app -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}')
mu=$(jp -n w-deploy get deploy rollout-app -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}')
if [ "$st" = "RollingUpdate" ] && [ "$ms" = "2" ] && [ "$mu" = "0" ]; then
  pass 6 "T2 rollout-app — RollingUpdate maxSurge=2 / maxUnavailable=0" $d
else
  fail 6 "T2 rollout-app — set a RollingUpdate strategy (maxSurge=2, maxUnavailable=0)" $d "type=${st:-∅}, maxSurge=${ms:-∅}, maxUnavailable=${mu:-∅}"
fi

# T3 — rolling update then rollback (9)
# The revision annotation counts template changes: create=1, update=2, undo=3.
d=WL
img13=$(jp -n w-roll get deploy rollver -o jsonpath='{.spec.template.spec.containers[0].image}')
rev13=$(jp -n w-roll get deploy rollver -o jsonpath="{.metadata.annotations['deployment\.kubernetes\.io/revision']}")
rr13=$(jp -n w-roll get deploy rollver -o jsonpath='{.status.readyReplicas}')
if [ "$img13" = "nginx:1.29-alpine" ] && [ "${rev13:-0}" -ge 3 ] && [ "${rr13:-0}" -ge 2 ]; then
  pass 9 "T3 rollver — updated then rolled back (revision ${rev13}, image restored)" $d
else
  fail 9 "T3 rollver — create, update the image, then roll back (final image nginx:1.29-alpine)" $d "image=${img13:-∅} (expected nginx:1.29-alpine), revision=${rev13:-∅} (expected ≥3), readyReplicas=${rr13:-0} (expected ≥2)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom BATCH 22 "⏱️  DaemonSets, Jobs & CronJobs"

# T4 — DaemonSet ready on all 3 nodes (8)
d=BATCH
nr=$(jp -n w-ds get daemonset node-agent -o jsonpath='{.status.numberReady}')
if [ "${nr:-0}" = "3" ]; then
  pass 8 "T4 node-agent — DaemonSet ready on all 3 nodes (tolerates every taint)" $d
else
  fail 8 "T4 node-agent — DaemonSet must run on ALL nodes incl. cp1 and a tainted w1" $d "numberReady=${nr:-0} (expected 3 — check tolerations)"
fi

# T5 — Job completed 3 times (7)
d=BATCH
sc=$(jp -n w-batch get job pi -o jsonpath='{.status.succeeded}')
if [ "${sc:-0}" = "3" ]; then
  pass 7 "T5 pi — Job reached 3 successful completions" $d
else
  fail 7 "T5 pi — create a Job 'pi' with completions=3" $d "succeeded=${sc:-0} (expected 3)"
fi

# T6 — CronJob schedule every minute (7, graded by spec)
d=BATCH
sch=$(jp -n w-batch get cronjob report -o jsonpath='{.spec.schedule}')
if [ "$sch" = "*/1 * * * *" ]; then
  pass 7 "T6 report — CronJob scheduled every minute" $d
else
  fail 7 "T6 report — create a CronJob 'report' with schedule '*/1 * * * *'" $d "schedule=${sch:-∅}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom RES 17 "📈 Autoscaling & QoS"

# T7 — HPA min1 max5 cpu50% (9)
d=RES
mn=$(jp -n w-hpa get hpa hpa-target -o jsonpath='{.spec.minReplicas}')
mx=$(jp -n w-hpa get hpa hpa-target -o jsonpath='{.spec.maxReplicas}')
cpu=$(jp -n w-hpa get hpa hpa-target -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')
if [ "$mn" = "1" ] && [ "$mx" = "5" ] && [ "$cpu" = "50" ]; then
  pass 9 "T7 hpa-target — HPA min=1 max=5 at 50% CPU" $d
else
  fail 9 "T7 hpa-target — autoscale 'hpa-target' (min=1, max=5, cpu=50%)" $d "min=${mn:-∅}, max=${mx:-∅}, cpu=${cpu:-∅}%"
fi

# T8 — Guaranteed QoS pod (8)
d=RES
qos=$(jp -n w-res get pod guaranteed -o jsonpath='{.status.qosClass}')
if [ "$qos" = "Guaranteed" ]; then
  pass 8 "T8 guaranteed — pod scheduled with QoS class Guaranteed" $d
else
  fail 8 "T8 guaranteed — create a pod whose QoS class is Guaranteed (requests==limits)" $d "qosClass=${qos:-absent}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SCHED 40 "🎯 Scheduling & Placement"

# T9 — nodeSelector onto w2 (disktype=ssd) (7)
d=SCHED
lbl=$(jp get node w2 -o jsonpath='{.metadata.labels.disktype}')
n8=$(jp -n w-sched get pod ssd-pod -o jsonpath='{.spec.nodeName}')
p8=$(jp -n w-sched get pod ssd-pod -o jsonpath='{.status.phase}')
if [ "$lbl" = "ssd" ] && [ "$n8" = "w2" ] && [ "$p8" = "Running" ]; then
  pass 7 "T9 ssd-pod — Running on w2 via nodeSelector disktype=ssd" $d
else
  fail 7 "T9 ssd-pod — label w2 disktype=ssd and pin 'ssd-pod' there with a nodeSelector" $d "w2 disktype=${lbl:-∅}, pod node=${n8:-none}, phase=${p8:-absent}"
fi

# T10 — nodeAffinity onto w2 (7)
d=SCHED
aff=$(jp -n w-sched get pod affinity-pod -o jsonpath='{.spec.affinity.nodeAffinity}')
n9=$(jp -n w-sched get pod affinity-pod -o jsonpath='{.spec.nodeName}')
p9=$(jp -n w-sched get pod affinity-pod -o jsonpath='{.status.phase}')
if [ -n "$aff" ] && [ "$n9" = "w2" ] && [ "$p9" = "Running" ]; then
  pass 7 "T10 affinity-pod — Running on w2 via required nodeAffinity" $d
else
  fail 7 "T10 affinity-pod — schedule 'affinity-pod' onto w2 using nodeAffinity (hostname)" $d "affinity set=$([ -n "$aff" ] && echo yes || echo no), node=${n9:-none}, phase=${p9:-absent}"
fi

# T11 — taint w1 + tolerating pod on w1 (9)
d=SCHED
taints=$(jp get node w1 -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect} {end}')
n10=$(jp -n w-taint get pod batch-pod -o jsonpath='{.spec.nodeName}')
p10=$(jp -n w-taint get pod batch-pod -o jsonpath='{.status.phase}')
if printf '%s' "$taints" | grep -q 'dedicated=batch:NoSchedule' && [ "$n10" = "w1" ] && [ "$p10" = "Running" ]; then
  pass 9 "T11 batch-pod — tolerates w1's taint and runs there" $d
else
  fail 9 "T11 batch-pod — taint w1 (dedicated=batch:NoSchedule) and run a tolerating pod on w1" $d "w1 taints=[${taints}], pod node=${n10:-none}, phase=${p10:-absent}"
fi

# T12 — topologySpreadConstraints spec (8, graded by spec)
d=SCHED
sms=$(jp -n w-spread get deploy spread-app -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].maxSkew}')
stk=$(jp -n w-spread get deploy spread-app -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].topologyKey}')
swu=$(jp -n w-spread get deploy spread-app -o jsonpath='{.spec.template.spec.topologySpreadConstraints[0].whenUnsatisfiable}')
if [ "$sms" = "1" ] && [ "$stk" = "kubernetes.io/hostname" ] && [ "$swu" = "ScheduleAnyway" ]; then
  pass 8 "T12 spread-app — topology spread maxSkew=1 over hostname (ScheduleAnyway)" $d
else
  fail 8 "T12 spread-app — add a topologySpreadConstraint (maxSkew=1, hostname, ScheduleAnyway)" $d "maxSkew=${sms:-∅}, topologyKey=${stk:-∅}, whenUnsatisfiable=${swu:-∅}"
fi

# T13 — PriorityClass + critical pod (9)
d=SCHED
pcv=$(jp get priorityclass high-priority -o jsonpath='{.value}')
pcn=$(jp -n w-prio get pod critical -o jsonpath='{.spec.priorityClassName}')
p12=$(jp -n w-prio get pod critical -o jsonpath='{.status.phase}')
if [ "$pcv" = "1000000" ] && [ "$pcn" = "high-priority" ] && [ "$p12" = "Running" ]; then
  pass 9 "T13 critical — pod running with PriorityClass high-priority (1000000)" $d
else
  fail 9 "T13 critical — create PriorityClass 'high-priority' (1000000) and use it on pod 'critical'" $d "class value=${pcv:-absent}, pod priorityClassName=${pcn:-∅}, phase=${p12:-absent}"
fi

# ══════════════════════════════════════════════════════════════════════════════
echo
echo "────────────────────────────────────────────────────────"
printf "\033[1mSubtotal per section:\033[0m\n"
order=(WL BATCH RES SCHED)
names=( "Deployments & Rollouts" "DaemonSets, Jobs & CronJobs" "Autoscaling & QoS" "Scheduling & Placement" )
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
