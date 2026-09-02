#!/usr/bin/env bash
# grade.sh — auto-grader for CKA mock exam #4 (killer.sh drills — session 2).
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/mock-exam/exam-04/grade.sh"
#
# Read-only: it changes NOTHING. Prints PASS/FAIL per task
# (with the symptom observed on failure, but NEVER the solution),
# subtotal per domain and total score. Pass ≥ 66%.
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX DOM_LABEL
ORDER=()

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
# dom KEY MAX "Label" — declares a domain and prints its header
dom()  { DOM_MAX[$1]=$2; DOM_LABEL[$1]=$3; ORDER+=("$1"); printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }
jp()   { kubectl "$@" 2>/dev/null; }

BASE=/opt/exam-04

# ══════════════════════════════════════════════════════════════════════════════
dom DNS 6 "🌐 DNS & Service discovery"

# T1 — 4 FQDNs in the ConfigMap (4) + Pods running with the values (3)
# The ConfigMap name is resolved from the Deployment's envFrom (survives a rename).
d=DNS
norm() { printf '%s' "$1" | tr -d '[:space:]' | sed 's/\.$//'; }
exp1="kubernetes.default.svc.cluster.local"
exp2="department.q4-workload.svc.cluster.local"
exp3="section100.section.q4-workload.svc.cluster.local"
exp4="1-2-3-4.kube-system.pod.cluster.local"
cmname=$(jp -n q4-control get deploy controller -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')
v1=$(norm "$(jp -n q4-control get cm "$cmname" -o jsonpath='{.data.DNS_1}')")
v2=$(norm "$(jp -n q4-control get cm "$cmname" -o jsonpath='{.data.DNS_2}')")
v3=$(norm "$(jp -n q4-control get cm "$cmname" -o jsonpath='{.data.DNS_3}')")
v4=$(norm "$(jp -n q4-control get cm "$cmname" -o jsonpath='{.data.DNS_4}')")
bad=""
[ "$v1" = "$exp1" ] || bad+="DNS_1=${v1:-∅}; "
[ "$v2" = "$exp2" ] || bad+="DNS_2=${v2:-∅}; "
[ "$v3" = "$exp3" ] || bad+="DNS_3=${v3:-∅} (must survive an IP change); "
[ "$v4" = "$exp4" ] || bad+="DNS_4=${v4:-∅}; "
if [ -n "$cmname" ] && [ -z "$bad" ]; then
  pass 3 "T1a ConfigMap ${cmname} — the 4 FQDNs are correct" $d
else
  fail 3 "T1a ConfigMap — set the 4 FQDNs (svc / headless / stable pod / pod by IP)" $d "${bad:-no ConfigMap referenced by the controller Deployment}"
fi
pod1=$(jp -n q4-control get pods -l app=controller --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
r1=$(norm "$(jp -n q4-control exec "$pod1" -- sh -c 'echo -n "$DNS_1"')")
r3=$(norm "$(jp -n q4-control exec "$pod1" -- sh -c 'echo -n "$DNS_3"')")
if [ "$r1" = "$exp1" ] && [ "$r3" = "$exp3" ]; then
  pass 3 "T1b controller Pods — running with the updated values" $d
else
  fail 3 "T1b controller Pods — the running Pods must see the new values" $d "runtime DNS_1=${r1:-∅}, DNS_3=${r3:-∅} — env vars from a ConfigMap are frozen at container start"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom STATIC 6 "🏛️  Static Pod & NodePort"

# T2 — mirror pod with requests (3) + Service with endpoint (2) + reachable on node IP (2)
d=STATIC
sp="my-static-pod-cp1"
ph2=$(jp -n default get pod $sp -o jsonpath='{.status.phase}')
own2=$(jp -n default get pod $sp -o jsonpath='{.metadata.ownerReferences[0].kind}')
img2=$(jp -n default get pod $sp -o jsonpath='{.spec.containers[0].image}')
rcpu=$(jp -n default get pod $sp -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
rmem=$(jp -n default get pod $sp -o jsonpath='{.spec.containers[0].resources.requests.memory}')
if [ "$ph2" = "Running" ] && [ "$own2" = "Node" ] && [ "$img2" = "nginx:1-alpine" ] && [ "$rcpu" = "10m" ] && [ "$rmem" = "20Mi" ]; then
  pass 2 "T2a my-static-pod — static Pod Running on cp1 (nginx:1-alpine, requests 10m/20Mi)" $d
else
  fail 2 "T2a my-static-pod — static Pod on cp1 with image nginx:1-alpine and requests 10m/20Mi" $d "phase=${ph2:-absent}, owner=${own2:-?}, image=${img2:-∅}, requests cpu=${rcpu:-∅}/mem=${rmem:-∅}"
fi
styp=$(jp -n default get svc static-pod-service -o jsonpath='{.spec.type}')
sport=$(jp -n default get svc static-pod-service -o jsonpath='{.spec.ports[0].port}')
eps2=$(jp -n default get endpoints static-pod-service -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
if [ "$styp" = "NodePort" ] && [ "$sport" = "80" ] && [ "${eps2:-0}" -ge 1 ]; then
  pass 2 "T2b static-pod-service — NodePort:80 with ${eps2} endpoint(s)" $d
else
  fail 2 "T2b static-pod-service — NodePort Service on port 80 with ≥ 1 endpoint" $d "type=${styp:-absent}, port=${sport:-∅}, endpoints=${eps2:-0} (selector matching the Pod labels?)"
fi
np2=$(jp -n default get svc static-pod-service -o jsonpath='{.spec.ports[0].nodePort}')
# buffer via $( ) — a live pipe into grep -q trips pipefail on SIGPIPE
page2=$(curl -m4 -s "http://192.168.56.10:${np2:-0}" 2>/dev/null)
if [ -n "$np2" ] && printf '%s' "$page2" | grep -qi nginx; then
  pass 2 "T2c reachable — curl 192.168.56.10:${np2} serves nginx" $d
else
  fail 2 "T2c reachable — the Pod must answer via the node's internal IP" $d "curl 192.168.56.10:${np2:-?} failed"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom KCERT 5 "🔐 Kubelet certificates"

# T3 — certificate-info.txt: client cert (2) + server cert (3)
# Deterministic markers: client issuer = cluster CA (CN=kubernetes), EKU clientAuth;
# server cert is self-signed by a per-node CA named "w1-ca@<ts>", EKU serverAuth.
d=KCERT
CERTF="$BASE/certificate-info.txt"
content=$(sudo cat "$CERTF" 2>/dev/null)
if printf '%s' "$content" | grep -q 'CN *= *kubernetes' && printf '%s' "$content" | grep -q 'TLS Web Client Authentication'; then
  pass 2 "T3a client cert — issuer (cluster CA) + EKU clientAuth reported" $d
else
  fail 2 "T3a client cert — report its Issuer and Extended Key Usage" $d "$( [ -n "$content" ] && echo "file lacks the client issuer (CN=kubernetes) and/or 'TLS Web Client Authentication'" || echo "$CERTF missing or empty" )"
fi
if printf '%s' "$content" | grep -q 'w1-ca@' && printf '%s' "$content" | grep -q 'TLS Web Server Authentication'; then
  pass 3 "T3b server cert — issuer (per-node CA) + EKU serverAuth reported" $d
else
  fail 3 "T3b server cert — report its Issuer and Extended Key Usage" $d "$( [ -n "$content" ] && echo "file lacks the server issuer (w1-ca@…) and/or 'TLS Web Server Authentication'" || echo "$CERTF missing or empty" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom PROBES 7 "🩺 Probes"

# T4 — probes configured (3) + am-i-ready endpoint (2) + first pod Ready (2)
d=PROBES
lp=$(jp -n default get pod ready-if-service-ready -o jsonpath='{.spec.containers[0].livenessProbe}')
rp=$(jp -n default get pod ready-if-service-ready -o jsonpath='{.spec.containers[0].readinessProbe}')
img4=$(jp -n default get pod ready-if-service-ready -o jsonpath='{.spec.containers[0].image}')
if printf '%s' "$lp" | grep -q 'true' && printf '%s' "$rp" | grep -q 'service-am-i-ready' && [ "$img4" = "nginx:1-alpine" ]; then
  pass 3 "T4a ready-if-service-ready — liveness (true) + readiness on service-am-i-ready" $d
else
  fail 3 "T4a ready-if-service-ready — configure the two probes as asked (nginx:1-alpine)" $d "livenessProbe=$([ -n "$lp" ] && echo set || echo ∅), readinessProbe references service-am-i-ready=$(printf '%s' "$rp" | grep -q 'service-am-i-ready' && echo yes || echo no), image=${img4:-∅}"
fi
lbl4=$(jp -n default get pod am-i-ready -o jsonpath='{.metadata.labels.id}')
eps4=$(jp -n default get endpoints service-am-i-ready -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
if [ "$lbl4" = "cross-server-ready" ] && [ "${eps4:-0}" -ge 1 ]; then
  pass 2 "T4b am-i-ready — labelled Pod is an endpoint of service-am-i-ready" $d
else
  fail 2 "T4b am-i-ready — create the labelled Pod so the Service gets an endpoint" $d "label id=${lbl4:-∅}, endpoints=${eps4:-0}"
fi
# Readiness may need one probe period to flip → wait up to 30 s.
rdy4=false
for _ in $(seq 1 6); do
  [ "$(jp -n default get pod ready-if-service-ready -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] && { rdy4=true; break; }
  sleep 5
done
if [ "$rdy4" = "true" ]; then
  pass 2 "T4c ready-if-service-ready — Ready (the readiness dependency is satisfied)" $d
else
  fail 2 "T4c ready-if-service-ready — the Pod must end up Ready" $d "Ready=False after 30 s — does the readiness command reach http://service-am-i-ready:80?"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom KCTL 4 "📋 kubectl — sorting"

# T5 — the two scripts must reference the right sort field AND actually run (2+2)
d=KCTL
check_script() { # $1=file $2=sort-field → sets sc_ok
  sc_ok=no
  if sudo test -f "$1" \
     && sudo grep -q 'kubectl' "$1" && sudo grep -qE '\-A|--all-namespaces' "$1" \
     && sudo grep -q 'sort-by' "$1" && sudo grep -q "$2" "$1" \
     && printf '%s' "$(timeout 30 bash "$1" 2>/dev/null)" | grep -q 'kube-system'; then
    sc_ok=yes
  fi
}
check_script "$BASE/find_pods.sh" 'metadata.creationTimestamp'
if [ "$sc_ok" = "yes" ]; then
  pass 2 "T5a find_pods.sh — pods sorted by creationTimestamp (script runs)" $d
else
  fail 2 "T5a find_pods.sh — all-namespaces listing sorted by metadata.creationTimestamp" $d "file missing, wrong sort field, or the script does not run"
fi
check_script "$BASE/find_pods_uid.sh" 'metadata.uid'
if [ "$sc_ok" = "yes" ]; then
  pass 2 "T5b find_pods_uid.sh — pods sorted by metadata.uid (script runs)" $d
else
  fail 2 "T5b find_pods_uid.sh — all-namespaces listing sorted by metadata.uid" $d "file missing, wrong sort field, or the script does not run"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom KLET 6 "🔧 Node troubleshooting"

# T6 — kubelet active (2) + cp1 Ready (3) + pod success (2)
d=KLET
if [ "$(sudo systemctl is-active kubelet 2>/dev/null)" = "active" ]; then
  pass 2 "T6a kubelet — service active (running) on cp1" $d
else
  fail 2 "T6a kubelet — the kubelet service must be running on cp1" $d "systemctl is-active kubelet = $(sudo systemctl is-active kubelet 2>/dev/null) — check every drop-in (systemctl cat kubelet)"
fi
rdy6=false
for _ in $(seq 1 6); do
  st=$(jp get node cp1 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  [ "$st" = "True" ] && { rdy6=true; break; }
  sleep 5
done
if [ "$rdy6" = "true" ]; then
  pass 2 "T6b node cp1 — back in Ready state" $d
else
  fail 2 "T6b node cp1 — must report Ready" $d "cp1 Ready=${st:-?} after 30 s (kubelet heartbeat missing?)"
fi
ph6=$(jp -n default get pod success -o jsonpath='{.status.phase}')
img6=$(jp -n default get pod success -o jsonpath='{.spec.containers[0].image}')
if [ "$ph6" = "Running" ] && [ "$img6" = "nginx:1-alpine" ]; then
  pass 2 "T6c pod success — Running (nginx:1-alpine)" $d
else
  fail 2 "T6c pod success — create it in default with image nginx:1-alpine" $d "phase=${ph6:-absent}, image=${img6:-∅}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom ETCD 5 "🗄️  etcd operations"

# T7 — version file (2) + valid snapshot (3)
d=ETCD
exp_ver=$(jp -n kube-system exec etcd-cp1 -- etcd --version 2>/dev/null | awk '/etcd Version/{print $3}')
got_ver=$(sudo cat "$BASE/etcd-version" 2>/dev/null)
if [ -n "$exp_ver" ] && printf '%s' "$got_ver" | grep -q "etcd Version: *${exp_ver}"; then
  pass 2 "T7a etcd-version — reports the real version (${exp_ver})" $d
else
  fail 2 "T7a etcd-version — store the output of 'etcd --version'" $d "$( [ -n "$got_ver" ] && echo "file does not contain 'etcd Version: ${exp_ver:-?}'" || echo "$BASE/etcd-version missing or empty" )"
fi
snap_ok=no
if sudo test -s "$BASE/etcd-snapshot.db"; then
  # etcdutl only exists inside the pod → validate via a throwaway copy under the shared hostPath.
  sudo cp "$BASE/etcd-snapshot.db" /var/lib/etcd/.grader-snap-check.db
  jp -n kube-system exec etcd-cp1 -- etcdutl snapshot status /var/lib/etcd/.grader-snap-check.db >/dev/null 2>&1 && snap_ok=yes
  sudo rm -f /var/lib/etcd/.grader-snap-check.db
fi
if [ "$snap_ok" = "yes" ]; then
  pass 3 "T7b etcd-snapshot.db — valid etcd snapshot" $d
else
  fail 3 "T7b etcd-snapshot.db — save a valid snapshot at $BASE/etcd-snapshot.db" $d "$( sudo test -s "$BASE/etcd-snapshot.db" && echo "file present but 'etcdutl snapshot status' rejects it" || echo "file missing or empty" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom COMP 5 "🏛️  Control plane components"

# T8 — 5 component types (3) + dns type & name (2)
d=COMP
COMPF="$BASE/controlplane-components.txt"
comp=$(sudo cat "$COMPF" 2>/dev/null)
bad8=""
printf '%s' "$comp" | grep -qiE '^kubelet: *process *$'                        || bad8+="kubelet; "
printf '%s' "$comp" | grep -qiE '^kube-apiserver: *static-pod *$'              || bad8+="kube-apiserver; "
printf '%s' "$comp" | grep -qiE '^kube-scheduler: *static-pod *$'              || bad8+="kube-scheduler; "
printf '%s' "$comp" | grep -qiE '^kube-controller-manager: *static-pod *$'     || bad8+="kube-controller-manager; "
printf '%s' "$comp" | grep -qiE '^etcd: *static-pod *$'                        || bad8+="etcd; "
if [ -z "$bad8" ] && [ -n "$comp" ]; then
  pass 3 "T8a components — the 5 start types are correct" $d
else
  fail 3 "T8a components — identify how each control-plane component is started" $d "$( [ -n "$comp" ] && echo "wrong or missing: ${bad8%; }" || echo "$COMPF missing or empty" )"
fi
if printf '%s' "$comp" | grep -qiE '^dns: *pod +coredns *$'; then
  pass 2 "T8b dns — pod coredns" $d
else
  fail 2 "T8b dns — report the DNS app's start type and name" $d "expected 'dns: pod coredns' (how does the DNS app run, and under which controller?)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SCHED 6 "🧠 Scheduler"

# T9 — scheduler healthy again (2) + manual pod on cp1 (3) + scheduled pod on a worker (2)
d=SCHED
sph=$(jp -n kube-system get pod kube-scheduler-cp1 -o jsonpath='{.status.phase}')
srdy=$(jp -n kube-system get pod kube-scheduler-cp1 -o jsonpath='{.status.containerStatuses[0].ready}')
if [ "$sph" = "Running" ] && [ "$srdy" = "true" ]; then
  pass 2 "T9a kube-scheduler — running again on cp1" $d
else
  fail 2 "T9a kube-scheduler — must be restarted and healthy" $d "kube-scheduler-cp1: phase=${sph:-absent}, ready=${srdy:-?}"
fi
n9a=$(jp -n default get pod manual-schedule -o jsonpath='{.spec.nodeName}')
p9a=$(jp -n default get pod manual-schedule -o jsonpath='{.status.phase}')
i9a=$(jp -n default get pod manual-schedule -o jsonpath='{.spec.containers[0].image}')
if [ "$n9a" = "cp1" ] && [ "$p9a" = "Running" ] && [ "$i9a" = "httpd:2-alpine" ]; then
  pass 2 "T9b manual-schedule — Running on cp1 (manually scheduled)" $d
else
  fail 2 "T9b manual-schedule — must run on cp1 (httpd:2-alpine)" $d "node=${n9a:-none}, phase=${p9a:-absent}, image=${i9a:-∅}"
fi
n9b=$(jp -n default get pod manual-schedule2 -o jsonpath='{.spec.nodeName}')
p9b=$(jp -n default get pod manual-schedule2 -o jsonpath='{.status.phase}')
i9b=$(jp -n default get pod manual-schedule2 -o jsonpath='{.spec.containers[0].image}')
case "$n9b" in w1|w2) wok=yes;; *) wok=no;; esac
if [ "$wok" = "yes" ] && [ "$p9b" = "Running" ] && [ "$i9b" = "httpd:2-alpine" ]; then
  pass 2 "T9c manual-schedule2 — Running on ${n9b} (scheduler is back)" $d
else
  fail 2 "T9c manual-schedule2 — must be scheduled on a worker by the restarted scheduler" $d "node=${n9b:-none}, phase=${p9b:-absent}, image=${i9b:-∅}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom STO 7 "💾 Storage — dynamic provisioning"

# T10 — SC fields (3) + PVC bound to an auto-provisioned PV (3) + Job completed with the PVC (2)
d=STO
prov=$(jp get sc local-backup -o jsonpath='{.provisioner}')
vbm=$(jp get sc local-backup -o jsonpath='{.volumeBindingMode}')
rpol=$(jp get sc local-backup -o jsonpath='{.reclaimPolicy}')
if [ "$prov" = "rancher.io/local-path" ] && [ "$vbm" = "WaitForFirstConsumer" ] && [ "$rpol" = "Retain" ]; then
  pass 2 "T10a local-backup — provisioner + WaitForFirstConsumer + Retain" $d
else
  fail 2 "T10a local-backup — StorageClass with the 3 required fields" $d "provisioner=${prov:-absent}, volumeBindingMode=${vbm:-∅}, reclaimPolicy=${rpol:-∅} (Retain = keep the PV on PVC deletion)"
fi
jobpvc=$(jp -n q4-backup get job backup -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}' | awk '{print $1}')
pvc_ok=no; pv_auto=no
if [ -n "$jobpvc" ]; then
  psz=$(jp -n q4-backup get pvc "$jobpvc" -o jsonpath='{.spec.resources.requests.storage}')
  psc=$(jp -n q4-backup get pvc "$jobpvc" -o jsonpath='{.spec.storageClassName}')
  pph=$(jp -n q4-backup get pvc "$jobpvc" -o jsonpath='{.status.phase}')
  pvname=$(jp -n q4-backup get pvc "$jobpvc" -o jsonpath='{.spec.volumeName}')
  [ "$psz" = "50Mi" ] && [ "$psc" = "local-backup" ] && [ "$pph" = "Bound" ] && pvc_ok=yes
  provby=$(jp get pv "$pvname" -o jsonpath="{.metadata.annotations['pv\.kubernetes\.io/provisioned-by']}")
  [ "$provby" = "rancher.io/local-path" ] && pv_auto=yes
fi
if [ "$pvc_ok" = "yes" ] && [ "$pv_auto" = "yes" ]; then
  pass 3 "T10b PVC ${jobpvc} — 50Mi/local-backup, Bound to auto-provisioned PV ${pvname}" $d
else
  fail 3 "T10b PVC — 50Mi, class local-backup, Bound to a provisioner-created PV" $d "job PVC=${jobpvc:-none}, size=${psz:-∅}, class=${psc:-∅}, phase=${pph:-∅}, PV provisioned-by=${provby:-∅} (manual PV = not accepted)"
fi
succ=$(jp -n q4-backup get job backup -o jsonpath='{.status.succeeded}')
if [ "${succ:-0}" -ge 1 ] && [ -n "$jobpvc" ]; then
  pass 2 "T10c Job backup — completed using the PVC" $d
else
  fail 2 "T10c Job backup — must complete once with the PVC mounted" $d "succeeded=${succ:-0}, PVC volume in the Job=${jobpvc:-none} (delete + re-create the Job to re-run it)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom SEC 7 "🔑 Secrets"

# T11 — pod running (2) + secret1 mounted ro (2) + secret2 as env (3)
d=SEC
ph11=$(jp -n q4-secret get pod secret-pod -o jsonpath='{.status.phase}')
img11=$(jp -n q4-secret get pod secret-pod -o jsonpath='{.spec.containers[0].image}')
if [ "$ph11" = "Running" ] && printf '%s' "$img11" | grep -q '^busybox:1'; then
  pass 2 "T11a secret-pod — Running in q4-secret (busybox:1)" $d
else
  fail 2 "T11a secret-pod — create the namespace and a running busybox:1 Pod" $d "phase=${ph11:-absent}, image=${img11:-∅}"
fi
vsec=$(jp -n q4-secret get pod secret-pod -o jsonpath='{.spec.volumes[?(@.secret.secretName=="secret1")].name}')
mnt=$(jp -n q4-secret get pod secret-pod -o jsonpath="{.spec.containers[0].volumeMounts[?(@.mountPath=='/tmp/secret1')].readOnly}")
live1=$(jp -n q4-secret exec secret-pod -- ls /tmp/secret1 2>/dev/null | grep -c halt)
if [ -n "$vsec" ] && [ "$mnt" = "true" ] && [ "${live1:-0}" -ge 1 ]; then
  pass 2 "T11b secret1 — mounted read-only at /tmp/secret1 (key visible)" $d
else
  fail 2 "T11b secret1 — create it from the file and mount it read-only at /tmp/secret1" $d "secret volume=${vsec:-none}, readOnly=${mnt:-∅}, key visible in container=$([ "${live1:-0}" -ge 1 ] && echo yes || echo no)"
fi
u11=$(jp -n q4-secret get secret secret2 -o jsonpath='{.data.user}' | base64 -d 2>/dev/null)
p11=$(jp -n q4-secret get secret secret2 -o jsonpath='{.data.pass}' | base64 -d 2>/dev/null)
au=$(jp -n q4-secret exec secret-pod -- sh -c 'echo -n "$APP_USER"' 2>/dev/null)
ap=$(jp -n q4-secret exec secret-pod -- sh -c 'echo -n "$APP_PASS"' 2>/dev/null)
if [ "$u11" = "user1" ] && [ "$p11" = "1234" ] && [ "$au" = "user1" ] && [ "$ap" = "1234" ]; then
  pass 3 "T11c secret2 — user/pass exposed as APP_USER/APP_PASS in the container" $d
else
  fail 3 "T11c secret2 — user=user1/pass=1234 available as APP_USER/APP_PASS" $d "secret2 user=${u11:-∅}/pass=${p11:-∅}, runtime APP_USER=${au:-∅}/APP_PASS=${ap:-∅}"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom TAINT 6 "🎯 Scheduling — taints & tolerations"

# T12 — pod/container names + image (2) + Running on cp1 (2) + toleration + selector (2)
d=TAINT
cn12=$(jp -n default get pod pod1 -o jsonpath='{.spec.containers[0].name}')
im12=$(jp -n default get pod pod1 -o jsonpath='{.spec.containers[0].image}')
if [ "$cn12" = "pod1-container" ] && [ "$im12" = "httpd:2-alpine" ]; then
  pass 2 "T12a pod1 — container pod1-container (httpd:2-alpine)" $d
else
  fail 2 "T12a pod1 — create it with container name pod1-container and image httpd:2-alpine" $d "container=${cn12:-absent}, image=${im12:-∅}"
fi
n12=$(jp -n default get pod pod1 -o jsonpath='{.spec.nodeName}')
p12b=$(jp -n default get pod pod1 -o jsonpath='{.status.phase}')
if [ "$n12" = "cp1" ] && [ "$p12b" = "Running" ]; then
  pass 2 "T12b pod1 — Running on the control-plane node" $d
else
  fail 2 "T12b pod1 — must run on cp1" $d "node=${n12:-none}, phase=${p12b:-absent}"
fi
tol12=$(jp -n default get pod pod1 -o jsonpath='{.spec.tolerations}')
sel12=$(jp -n default get pod pod1 -o jsonpath='{.spec.nodeSelector}{.spec.affinity}')
if printf '%s' "$tol12" | grep -q 'node-role.kubernetes.io/control-plane' && printf '%s' "$sel12" | grep -q 'node-role.kubernetes.io/control-plane'; then
  pass 2 "T12c pod1 — control-plane toleration + selector on the existing label" $d
else
  fail 2 "T12c pod1 — tolerate the control-plane taint AND select the control-plane label (no nodeName)" $d "toleration=$(printf '%s' "$tol12" | grep -q control-plane && echo yes || echo no), selector/affinity on control-plane label=$(printf '%s' "$sel12" | grep -q control-plane && echo yes || echo no)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom MULTI 7 "🧭 Multi-container Pods"

# T13 — 3 containers (2) + emptyDir mounted everywhere (2) + MY_NODE_NAME (1) + c3 logs (2)
d=MULTI
MCP=multi-container-playground
p13=$(jp -n default get pod $MCP -o jsonpath='{.status.phase}')
names13=$(jp -n default get pod $MCP -o jsonpath='{range .spec.containers[*]}{.name}={.image} {end}')
ok_n=yes
printf '%s' "$names13" | grep -q 'c1=nginx:1-alpine'  || ok_n=no
printf '%s' "$names13" | grep -q 'c2=busybox:1'       || ok_n=no
printf '%s' "$names13" | grep -q 'c3=busybox:1'       || ok_n=no
if [ "$p13" = "Running" ] && [ "$ok_n" = "yes" ]; then
  pass 2 "T13a $MCP — Running with c1/c2/c3 and the right images" $d
else
  fail 2 "T13a $MCP — 3 containers c1(nginx:1-alpine), c2/c3(busybox:1), Running" $d "phase=${p13:-absent}, containers=[${names13:-none}]"
fi
vol13=$(jp -n default get pod $MCP -o jsonpath='{.spec.volumes[?(@.emptyDir)].name}' | awk '{print $1}')
mnt_count=0
for i in 0 1 2; do
  m=$(jp -n default get pod $MCP -o jsonpath="{.spec.containers[$i].volumeMounts[?(@.name=='$vol13')].mountPath}")
  [ -n "$m" ] && mnt_count=$((mnt_count+1))
done
if [ -n "$vol13" ] && [ "$mnt_count" = "3" ]; then
  pass 2 "T13b volume — emptyDir '${vol13}' mounted in the 3 containers" $d
else
  fail 2 "T13b volume — an emptyDir mounted into each container" $d "emptyDir volume=${vol13:-none}, containers mounting it=${mnt_count}/3 (« not persisted, not shared » = emptyDir)"
fi
real_node=$(jp -n default get pod $MCP -o jsonpath='{.spec.nodeName}')
env_node=$(jp -n default exec $MCP -c c1 -- sh -c 'echo -n "$MY_NODE_NAME"' 2>/dev/null)
if [ -n "$real_node" ] && [ "$env_node" = "$real_node" ]; then
  pass 1 "T13c c1 — MY_NODE_NAME=${env_node}" $d
else
  fail 1 "T13c c1 — MY_NODE_NAME must hold the node name (Downward API)" $d "runtime MY_NODE_NAME=${env_node:-∅}, actual node=${real_node:-?}"
fi
if printf '%s' "$(jp -n default logs $MCP -c c3 --tail=5)" | grep -qE '[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
  pass 2 "T13d c3 — date.log content streamed to stdout" $d
else
  fail 2 "T13d c3 — its logs must show the dates written by c2" $d "no date lines in 'kubectl logs $MCP -c c3' (shared mount paths consistent between c2 and c3?)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom INFO 5 "🔎 Cluster introspection"

# T14 — 5 answers, 1 pt each; ground truth computed live where possible
d=INFO
INFOF="$BASE/cluster-info"
info=$(sudo cat "$INFOF" 2>/dev/null)
exp_cp=$(jp get nodes -l node-role.kubernetes.io/control-plane --no-headers | grep -c .)
exp_wk=$(jp get nodes --no-headers | grep -c . ); exp_wk=$((exp_wk - exp_cp))
exp_cidr=$(sudo grep -oP 'service-cluster-ip-range=\K\S+' /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null)
if [ -z "$info" ]; then
  fail 5 "T14 cluster-info — answer the 5 questions in $INFOF" $d "file missing or empty"
else
  bad14=""
  printf '%s' "$info" | grep -qE "^1: *${exp_cp} *$"            || bad14+="1 (control-plane count); "
  printf '%s' "$info" | grep -qE "^2: *${exp_wk} *$"            || bad14+="2 (worker count); "
  printf '%s' "$info" | grep -qE "^3: *${exp_cidr//./\\.} *$"   || bad14+="3 (Service CIDR); "
  printf '%s' "$info" | grep -iE '^4:' | grep -qi 'calico'       || bad14+="4 (CNI plugin); "
  printf '%s' "$info" | grep -iE '^4:' | grep -q '/etc/cni/net.d' || bad14+="4 (CNI config path); "
  printf '%s' "$info" | grep -qE '^5: *-?cp1 *$'                 || bad14+="5 (static pod suffix); "
  if [ -z "$bad14" ]; then
    pass 5 "T14 cluster-info — the 5 answers are correct" $d
  else
    fail 5 "T14 cluster-info — some answers are wrong or missing" $d "check: ${bad14%; }"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
dom EVT 6 "📰 Events & container runtime"

# T15 — events script (2) + pod-kill log (2) + container-kill log (2)
d=EVT
EVSH="$BASE/cluster_events.sh"
ev_ok=no
if sudo test -f "$EVSH" && sudo grep -q 'kubectl' "$EVSH" \
   && sudo grep -qE '\-A|--all-namespaces' "$EVSH" \
   && sudo grep -q 'sort-by' "$EVSH" && sudo grep -q 'metadata.creationTimestamp' "$EVSH" \
   && [ -n "$(timeout 30 bash "$EVSH" 2>/dev/null)" ]; then
  ev_ok=yes
fi
if [ "$ev_ok" = "yes" ]; then
  pass 2 "T15a cluster_events.sh — cluster-wide events sorted by creationTimestamp" $d
else
  fail 2 "T15a cluster_events.sh — working kubectl events command (all namespaces, sorted)" $d "file missing, wrong sort field, or the script does not run"
fi
plog=$(sudo cat "$BASE/pod_kill.log" 2>/dev/null)
if printf '%s' "$plog" | grep -q 'kube-proxy' && printf '%s' "$plog" | grep -qE 'Killing|SuccessfulCreate|Scheduled|Started|Pulled'; then
  pass 2 "T15b pod_kill.log — events of the kube-proxy Pod deletion captured" $d
else
  fail 2 "T15b pod_kill.log — must contain the events caused by deleting the kube-proxy Pod" $d "$( [ -n "$plog" ] && echo "no kube-proxy pod-lifecycle events found in the file" || echo "file missing or empty" )"
fi
clog=$(sudo cat "$BASE/container_kill.log" 2>/dev/null)
if printf '%s' "$clog" | grep -q 'kube-proxy' && printf '%s' "$clog" | grep -qE 'Created|Started|Pulled|BackOff'; then
  pass 2 "T15c container_kill.log — events of the container kill captured" $d
else
  fail 2 "T15c container_kill.log — must contain the events caused by killing the container" $d "$( [ -n "$clog" ] && echo "no kube-proxy container-restart events found in the file" || echo "file missing or empty" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom RES 5 "🗂️  API resources & Namespaces"

# T16 — namespaced resources list (3) + most crowded project-* namespace (2)
d=RES
RESF="$BASE/resources.txt"
missing16=$(comm -23 <(kubectl api-resources --namespaced -o name 2>/dev/null | sort -u) \
                    <(sudo sort -u "$RESF" 2>/dev/null) | head -3 | tr '\n' ' ')
if sudo test -s "$RESF" && [ -z "$missing16" ]; then
  pass 3 "T16a resources.txt — all namespaced resources listed" $d
else
  fail 3 "T16a resources.txt — list every namespaced resource (-o name)" $d "$( sudo test -s "$RESF" && echo "missing entries, e.g.: ${missing16}…" || echo "$RESF missing or empty" )"
fi
best_ns=""; best_n=-1
for ns in $(jp get ns -o name | sed 's|namespace/||' | grep '^project-'); do
  n=$(jp -n "$ns" get roles --no-headers 2>/dev/null | grep -c .)
  if [ "$n" -gt "$best_n" ]; then best_n=$n; best_ns=$ns; fi
done
crowd=$(sudo cat "$BASE/crowded-namespace.txt" 2>/dev/null)
if [ -n "$best_ns" ] && printf '%s' "$crowd" | grep -q "$best_ns" && printf '%s' "$crowd" | grep -qw "$best_n"; then
  pass 2 "T16b crowded-namespace.txt — ${best_ns} with ${best_n} Roles" $d
else
  fail 2 "T16b crowded-namespace.txt — name the project-* namespace with the most Roles + the count" $d "$( [ -n "$crowd" ] && echo "expected '${best_ns}' and '${best_n}' in the file" || echo "file missing or empty" )"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom KUST 7 "🧩 Kustomize & RBAC"

# T17 — Role covers the 3 CRDs (3) + operator logs clean (2) + student4 in cluster AND config (3)
d=KUST
SA17="system:serviceaccount:q4-operator:operator-sa"
bad17=""
for r in students teachers courses; do
  [ "$(jp auth can-i list "$r.education.cka.local" --as="$SA17" -n q4-operator)" = "yes" ] || bad17+="$r; "
done
if [ -z "$bad17" ]; then
  pass 3 "T17a operator-role — list granted on the 3 education CRDs" $d
else
  fail 3 "T17a operator-role — grant list on every CRD the operator uses" $d "SA still cannot list: ${bad17%; } (check the operator logs)"
fi
logs_ok=no
for _ in $(seq 1 5); do
  recent=$(jp -n q4-operator logs deploy/operator --tail=3 2>/dev/null)
  if [ -n "$recent" ] && ! printf '%s' "$recent" | grep -q 'ERROR'; then logs_ok=yes; break; fi
  sleep 8
done
if [ "$logs_ok" = "yes" ]; then
  pass 2 "T17b operator — logs are error-free (all lists succeed)" $d
else
  fail 2 "T17b operator — its logs must show no more RBAC errors" $d "still ERROR lines in the last log entries after 40 s"
fi
s4=$(jp -n q4-operator get student student4 -o name 2>/dev/null)
render4=$(kubectl kustomize "$BASE/operator/prod" 2>/dev/null | grep -c 'name: student4')
if [ -n "$s4" ] && [ "${render4:-0}" -ge 1 ]; then
  pass 2 "T17c student4 — present in the cluster and in the Kustomize config" $d
else
  fail 2 "T17c student4 — add it to the BASE config and deploy via Kustomize" $d "in cluster=$([ -n "$s4" ] && echo yes || echo no), in rendered config=$([ "${render4:-0}" -ge 1 ] && echo yes || echo no)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
TOTAL=0; GOT=0
printf "\n────────────────────────────────────────────────────────\n"
printf "Subtotals per domain:\n"
for k in "${ORDER[@]}"; do
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
