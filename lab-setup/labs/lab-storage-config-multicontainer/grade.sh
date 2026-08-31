#!/usr/bin/env bash
# grade.sh — auto-grader for the "Storage · ConfigMap/Secrets · Sidecars" lab.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-storage-config-multicontainer/grade.sh"
#
# Makes NO changes: read-only (get/exec). Prints PASS/FAIL per task
# (with the observed symptom on failure, but NEVER the solution),
# a subtotal per section and a total score. Target ≥ 75 %.
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }

phase()   { kubectl -n "$1" get pod "$2" -o jsonpath='{.status.phase}' 2>/dev/null; }

# ══════════════════════════════════════════════════════════════════════════════
dom STO 40 "💾 Persistent storage"
d=STO

# ── A1 — StorageClass fast-local (provisioner+VBM 4 + reclaim+expansion 4) ──
prov=$(kubectl get sc fast-local -o jsonpath='{.provisioner}' 2>/dev/null)
vbm=$(kubectl get sc fast-local -o jsonpath='{.volumeBindingMode}' 2>/dev/null)
rp=$(kubectl get sc fast-local -o jsonpath='{.reclaimPolicy}' 2>/dev/null)
ave=$(kubectl get sc fast-local -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null)
if [ "$prov" = "example.com/fast-provisioner" ] && [ "$vbm" = "WaitForFirstConsumer" ]; then
  pass 4 "A1a fast-local — provisioner + volumeBindingMode WaitForFirstConsumer" $d
else
  r=""
  [ "$prov" = "example.com/fast-provisioner" ] || r+="provisioner=${prov:-absent}; "
  [ "$vbm" = "WaitForFirstConsumer" ]          || r+="volumeBindingMode=${vbm:-absent}(≠WaitForFirstConsumer); "
  fail 4 "A1a fast-local — provisioner + WaitForFirstConsumer" $d "${r%; }"
fi
if [ "$rp" = "Retain" ] && [ "$ave" = "true" ]; then
  pass 4 "A1b fast-local — reclaimPolicy Retain + allowVolumeExpansion" $d
else
  r=""
  [ "$rp" = "Retain" ]  || r+="reclaimPolicy=${rp:-absent}(≠Retain); "
  [ "$ave" = "true" ]   || r+="allowVolumeExpansion=${ave:-absent}(≠true); "
  fail 4 "A1b fast-local — Retain + expansion enabled" $d "${r%; }"
fi

# ── A2 — PVC app-data bound to pv-data (Bound 5 + volumeName 5) ──
ph=$(kubectl -n storage-lab get pvc app-data -o jsonpath='{.status.phase}' 2>/dev/null)
vol=$(kubectl -n storage-lab get pvc app-data -o jsonpath='{.spec.volumeName}' 2>/dev/null)
if [ "$ph" = "Bound" ]; then
  pass 5 "A2a app-data — PVC Bound" $d
else
  fail 5 "A2a app-data — PVC Bound" $d "phase=${ph:-absent} (storageClassName=manual? size ≤ 5Gi? RWO?)"
fi
if [ "$vol" = "pv-data" ]; then
  pass 5 "A2b app-data — bound precisely to pv-data" $d
else
  fail 5 "A2b app-data — volumeName pv-data" $d "volumeName=${vol:-absent}(≠pv-data)"
fi

# ── A3 — Pod app mounts app-data on /data + ready file (run 3 + mount 4 + file 3) ──
run=$(phase storage-lab app)
claim=$(kubectl -n storage-lab get pod app -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim.claimName=="app-data")].name}' 2>/dev/null)
mnt=$(kubectl -n storage-lab get pod app -o jsonpath='{.spec.containers[*].volumeMounts[?(@.mountPath=="/data")].name}' 2>/dev/null)
if [ "$run" = "Running" ]; then
  pass 3 "A3a app — Pod Running" $d
else
  fail 3 "A3a app — Pod Running" $d "phase=${run:-absent}"
fi
if [ -n "$claim" ] && printf '%s' "$mnt" | grep -qw "$claim"; then
  pass 4 "A3b app — app-data PVC volume mounted on /data" $d
else
  fail 4 "A3b app — app-data PVC mounted on /data" $d "app-data PVC volume=${claim:-absent}, /data mounts=${mnt:-none}"
fi
if [ "$run" = "Running" ] && kubectl -n storage-lab exec app -- test -f /data/ready >/dev/null 2>&1; then
  pass 3 "A3c app — /data/ready file present" $d
else
  fail 3 "A3c app — /data/ready file present" $d "test -f /data/ready fails (Pod not Running or file missing)"
fi

# ── A4 — pv-archive unblocked + archive PVC bound (pv 4 + Bound 4 + volumeName 4) ──
pvph=$(kubectl get pv pv-archive -o jsonpath='{.status.phase}' 2>/dev/null)
if [ -n "$pvph" ] && [ "$pvph" != "Released" ]; then
  pass 4 "A4a pv-archive — unblocked (no longer Released)" $d
else
  fail 4 "A4a pv-archive — remove the stale claimRef" $d "phase=${pvph:-absent} (expected Available or Bound)"
fi
aph=$(kubectl -n storage-lab get pvc archive -o jsonpath='{.status.phase}' 2>/dev/null)
avol=$(kubectl -n storage-lab get pvc archive -o jsonpath='{.spec.volumeName}' 2>/dev/null)
if [ "$aph" = "Bound" ]; then
  pass 4 "A4b archive — PVC Bound" $d
else
  fail 4 "A4b archive — PVC Bound" $d "phase=${aph:-absent} (PV still Released? PVC created?)"
fi
if [ "$avol" = "pv-archive" ]; then
  pass 4 "A4c archive — bound to pv-archive" $d
else
  fail 4 "A4c archive — volumeName pv-archive" $d "volumeName=${avol:-absent}(≠pv-archive)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom CFG 35 "⚙️ ConfigMap & Secrets"
d=CFG
NS=config-lab

# ── B1 — ConfigMap app-config (APP_MODE+LOG_LEVEL 4 + MAX_CONNECTIONS 4) ──
m=$(kubectl -n $NS get cm app-config -o jsonpath='{.data.APP_MODE}' 2>/dev/null)
l=$(kubectl -n $NS get cm app-config -o jsonpath='{.data.LOG_LEVEL}' 2>/dev/null)
c=$(kubectl -n $NS get cm app-config -o jsonpath='{.data.MAX_CONNECTIONS}' 2>/dev/null)
if [ "$m" = "production" ] && [ "$l" = "info" ]; then
  pass 4 "B1a app-config — APP_MODE=production, LOG_LEVEL=info" $d
else
  r=""
  [ "$m" = "production" ] || r+="APP_MODE=${m:-absent}; "
  [ "$l" = "info" ]       || r+="LOG_LEVEL=${l:-absent}; "
  fail 4 "B1a app-config — APP_MODE + LOG_LEVEL" $d "${r%; }"
fi
if [ "$c" = "100" ]; then
  pass 4 "B1b app-config — MAX_CONNECTIONS=100" $d
else
  fail 4 "B1b app-config — MAX_CONNECTIONS=100" $d "MAX_CONNECTIONS=${c:-absent}"
fi

# ── B2 — Secret db-credentials (Opaque+username 3 + password 4) ──
ty=$(kubectl -n $NS get secret db-credentials -o jsonpath='{.type}' 2>/dev/null)
u=$(kubectl -n $NS get secret db-credentials -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null)
p=$(kubectl -n $NS get secret db-credentials -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
if [ "$ty" = "Opaque" ] && [ "$u" = "admin" ]; then
  pass 3 "B2a db-credentials — Opaque + username=admin" $d
else
  r=""
  [ "$ty" = "Opaque" ] || r+="type=${ty:-absent}(≠Opaque); "
  [ "$u" = "admin" ]   || r+="username=${u:-absent}; "
  fail 3 "B2a db-credentials — Opaque + username=admin" $d "${r%; }"
fi
if [ "$p" = "S3cr3t-pass" ]; then
  pass 4 "B2b db-credentials — password correct" $d
else
  fail 4 "B2b db-credentials — password=S3cr3t-pass" $d "decoded password=${p:-absent}"
fi

# ── B3 — Pod api: envFrom + secretKeyRef (APP_MODE 3 + MAX_CONNECTIONS 2 + DB_PASSWORD 5) ──
run=$(phase $NS api)
if [ "$run" = "Running" ]; then
  am=$(kubectl -n $NS exec api -- printenv APP_MODE 2>/dev/null | tr -d '\r')
  mc=$(kubectl -n $NS exec api -- printenv MAX_CONNECTIONS 2>/dev/null | tr -d '\r')
  dp=$(kubectl -n $NS exec api -- printenv DB_PASSWORD 2>/dev/null | tr -d '\r')
else
  am=""; mc=""; dp=""
fi
if [ "$am" = "production" ]; then
  pass 3 "B3a api — APP_MODE injected via envFrom" $d
else
  fail 3 "B3a api — APP_MODE via envFrom app-config" $d "APP_MODE=${am:-absent} (Pod Running? envFrom configMapRef app-config?)"
fi
if [ "$mc" = "100" ]; then
  pass 2 "B3b api — MAX_CONNECTIONS injected via envFrom" $d
else
  fail 2 "B3b api — MAX_CONNECTIONS via envFrom" $d "MAX_CONNECTIONS=${mc:-absent}"
fi
if [ "$dp" = "S3cr3t-pass" ]; then
  pass 5 "B3c api — DB_PASSWORD injected via secretKeyRef" $d
else
  fail 5 "B3c api — DB_PASSWORD via secretKeyRef (password key)" $d "DB_PASSWORD=${dp:-absent}"
fi

# ── B4 — ConfigMap web-index as a volume (key 3 + served file 7) ──
idx=$(kubectl -n $NS get cm web-index -o jsonpath='{.data.index\.html}' 2>/dev/null)
if printf '%s' "$idx" | grep -q 'CKA Storage Lab'; then
  pass 3 "B4a web-index — index.html key contains the marker" $d
else
  fail 3 "B4a web-index — index.html key (marker 'CKA Storage Lab')" $d "index.html key missing or without the marker"
fi
served=$(kubectl -n $NS exec web -- cat /usr/share/nginx/html/index.html 2>/dev/null)
if printf '%s' "$served" | grep -q 'CKA Storage Lab'; then
  pass 7 "B4b web — /usr/share/nginx/html/index.html served from the ConfigMap" $d
else
  fail 7 "B4b web — ConfigMap mounted on /usr/share/nginx/html" $d "the served file does not contain the marker (Pod Running? configMap web-index volume?)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom MUL 25 "🧩 Sidecars & multi-container"
d=MUL
NS=multi-lab

# ── C1 — shared-logs: shared emptyDir (run+2c 4 + mount 4 + file 5) ──
run=$(phase $NS shared-logs)
ccount=$(kubectl -n $NS get pod shared-logs -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | wc -w)
if [ "$run" = "Running" ] && [ "$ccount" -ge 2 ]; then
  pass 4 "C1a shared-logs — Running with 2 containers" $d
else
  fail 4 "C1a shared-logs — Running, 2 containers" $d "phase=${run:-absent}, containers=$ccount"
fi
ed=$(kubectl -n $NS get pod shared-logs -o jsonpath='{.spec.volumes[*].emptyDir}' 2>/dev/null)
mounts=$(kubectl -n $NS get pod shared-logs -o jsonpath='{.spec.containers[*].volumeMounts[?(@.mountPath=="/var/log/app")].name}' 2>/dev/null | wc -w)
if [ -n "$ed" ] && [ "$mounts" -ge 2 ]; then
  pass 4 "C1b shared-logs — emptyDir mounted on /var/log/app (2 containers)" $d
else
  fail 4 "C1b shared-logs — shared emptyDir on /var/log/app" $d "emptyDir present=$([ -n "$ed" ] && echo yes || echo no), /var/log/app mounts=$mounts (expected 2)"
fi
if [ "$run" = "Running" ] && [ -n "$(kubectl -n $NS exec shared-logs -c sidecar -- cat /var/log/app/app.log 2>/dev/null)" ]; then
  pass 5 "C1c shared-logs — shared app.log non-empty (writer↔sidecar)" $d
else
  fail 5 "C1c shared-logs — the sidecar reads /var/log/app/app.log" $d "empty/missing file (does the writer write to /var/log/app/app.log? 'sidecar' container?)"
fi

# ── C2 — web-agent: native sidecar (restartPolicy 6 + Running/active 6) ──
rpol=$(kubectl -n $NS get pod web-agent -o jsonpath='{.spec.initContainers[?(@.name=="log-agent")].restartPolicy}' 2>/dev/null)
if [ "$rpol" = "Always" ]; then
  pass 6 "C2a web-agent — native sidecar log-agent (initContainer restartPolicy Always)" $d
else
  fail 6 "C2a web-agent — initContainer log-agent with restartPolicy Always" $d "restartPolicy(log-agent)=${rpol:-absent} (expected Always)"
fi
ph=$(phase $NS web-agent)
side=$(kubectl -n $NS get pod web-agent -o jsonpath='{.status.initContainerStatuses[?(@.name=="log-agent")].state.running.startedAt}' 2>/dev/null)
if [ "$ph" = "Running" ] && [ -n "$side" ]; then
  pass 6 "C2b web-agent — Pod Running and sidecar log-agent active" $d
else
  fail 6 "C2b web-agent — Pod Running, sidecar active" $d "phase=${ph:-absent}, sidecar active=$([ -n "$side" ] && echo yes || echo no)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
TOTAL=0; GOT=0
printf "\n────────────────────────────────────────────────────────\n"
printf "Subtotal per section:\n"
declare -A DOM_LABEL=( [STO]="Storage" [CFG]="ConfigMap & Secrets" [MUL]="Multi-container" )
for k in STO CFG MUL; do
  [ -n "${DOM_MAX[$k]:-}" ] || continue
  printf "  %-24s %2d / %d\n" "${DOM_LABEL[$k]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
  TOTAL=$((TOTAL + DOM_MAX[$k])); GOT=$((GOT + ${DOM_GOT[$k]:-0}))
done
printf "────────────────────────────────────────────────────────\n"
printf "TOTAL SCORE : %d / %d\n" "$GOT" "$TOTAL"
if [ "$TOTAL" -gt 0 ] && [ $((GOT*100/TOTAL)) -ge 75 ]; then
  printf "\033[32m🎉 TARGET REACHED (≥ 75%%)\033[0m\n"
else
  printf "\033[31mKEEP PRACTISING (< 75%%)\033[0m\n"
fi
printf "────────────────────────────────────────────────────────\n"
