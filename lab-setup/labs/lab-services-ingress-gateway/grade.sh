#!/usr/bin/env bash
# grade.sh — auto-grader for the "Services · Ingress · Gateway API" lab.
# Run ON cp1:  vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"
#
# Read-only: it changes NOTHING. Prints PASS/FAIL per task
# (with the observed symptom on failure, but NEVER the solution),
# a subtotal per domain and a total score. Target ≥ 75 %.
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }

# Number of Endpoints addresses of a Service (ns, name)
ep_count() { kubectl -n "$1" get endpoints "$2" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w; }
# TCP connection from the probe Pod to <clusterIP:port> (via agnhost)
probe_connect() { kubectl -n services-lab exec probe -- /agnhost connect "$1" --timeout=3s >/dev/null 2>&1; }

# ══════════════════════════════════════════════════════════════════════════════
dom SVC 40 "🔌 Services"
d=SVC
NS=services-lab

# ── A1 — ClusterIP web-svc (spec 5 + endpoints/connectivity 5) ──
t=$(kubectl -n $NS get svc web-svc -o jsonpath='{.spec.type}' 2>/dev/null)
po=$(kubectl -n $NS get svc web-svc -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
tp=$(kubectl -n $NS get svc web-svc -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
se=$(kubectl -n $NS get svc web-svc -o jsonpath='{.spec.selector.app}' 2>/dev/null)
if [ "$t" = "ClusterIP" ] && [ "$po" = "80" ] && [ "$tp" = "80" ] && [ "$se" = "web" ]; then
  pass 5 "A1a web-svc — ClusterIP, port 80→80, selector app=web" $d
else
  r=""
  [ "$t" = "ClusterIP" ] || r+="type=${t:-absent}(≠ClusterIP); "
  [ "$po" = "80" ]       || r+="port=${po:-absent}(≠80); "
  [ "$tp" = "80" ]       || r+="targetPort=${tp:-absent}(≠80); "
  [ "$se" = "web" ]      || r+="selector.app=${se:-absent}(≠web); "
  fail 5 "A1a web-svc — ClusterIP 80→80 selector app=web" $d "${r%; }"
fi
cip=$(kubectl -n $NS get svc web-svc -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ "$(ep_count $NS web-svc)" -ge 2 ] && [ -n "$cip" ] && probe_connect "$cip:80"; then
  pass 5 "A1b web-svc — 2 endpoints ready and reachable on :80" $d
else
  fail 5 "A1b web-svc — populated endpoints + connection :80 OK" $d \
    "endpoints=$(ep_count $NS web-svc) (expected ≥2) or connection clusterIP:80 refused (selector/targetPort ?)"
fi

# ── A2 — NodePort web-np (type+nodePort 5 + mapping 3) ──
t=$(kubectl -n $NS get svc web-np -o jsonpath='{.spec.type}' 2>/dev/null)
np=$(kubectl -n $NS get svc web-np -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
if [ "$t" = "NodePort" ] && [ "$np" = "30080" ]; then
  pass 5 "A2a web-np — type NodePort, nodePort 30080" $d
else
  r=""
  [ "$t" = "NodePort" ] || r+="type=${t:-absent}(≠NodePort); "
  [ "$np" = "30080" ]   || r+="nodePort=${np:-absent}(≠30080); "
  fail 5 "A2a web-np — NodePort on 30080" $d "${r%; }"
fi
po=$(kubectl -n $NS get svc web-np -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
tp=$(kubectl -n $NS get svc web-np -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
se=$(kubectl -n $NS get svc web-np -o jsonpath='{.spec.selector.app}' 2>/dev/null)
if [ "$po" = "80" ] && [ "$tp" = "80" ] && [ "$se" = "web" ]; then
  pass 3 "A2b web-np — port 80→80, selector app=web" $d
else
  fail 3 "A2b web-np — port 80→80 selector app=web" $d "port=${po:-absent} targetPort=${tp:-absent} selector.app=${se:-absent}"
fi

# ── A3 — Service headless cache-hl (spec 5 + endpoints 3) ──
ci=$(kubectl -n $NS get svc cache-hl -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
se=$(kubectl -n $NS get svc cache-hl -o jsonpath='{.spec.selector.app}' 2>/dev/null)
po=$(kubectl -n $NS get svc cache-hl -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
if [ "$ci" = "None" ] && [ "$se" = "cache" ] && [ "$po" = "80" ]; then
  pass 5 "A3a cache-hl — headless (clusterIP None), selector app=cache, port 80" $d
else
  r=""
  [ "$ci" = "None" ]  || r+="clusterIP=${ci:-absent}(≠None → not headless); "
  [ "$se" = "cache" ] || r+="selector.app=${se:-absent}(≠cache); "
  [ "$po" = "80" ]    || r+="port=${po:-absent}(≠80); "
  fail 5 "A3a cache-hl — headless selector app=cache port 80" $d "${r%; }"
fi
if [ "$(ep_count $NS cache-hl)" -ge 2 ]; then
  pass 3 "A3b cache-hl — 2 Pod addresses in the endpoints" $d
else
  fail 3 "A3b cache-hl — endpoints list the cache Pod IPs" $d "endpoints=$(ep_count $NS cache-hl) (expected ≥2)"
fi

# ── A4 — Service WITHOUT selector + manual Endpoints (svc 3 + ep 3 + connect 2) ──
if kubectl -n $NS get svc db-ext >/dev/null 2>&1; then
  se=$(kubectl -n $NS get svc db-ext -o jsonpath='{.spec.selector}' 2>/dev/null)
  po=$(kubectl -n $NS get svc db-ext -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  if [ -z "$se" ] && [ "$po" = "5432" ]; then
    pass 3 "A4a db-ext — Service without selector, port 5432" $d
  else
    r=""
    [ -z "$se" ]        || r+="a selector is defined (must be absent); "
    [ "$po" = "5432" ]  || r+="port=${po:-absent}(≠5432); "
    fail 3 "A4a db-ext — Service without selector, port 5432" $d "${r%; }"
  fi
else
  fail 3 "A4a db-ext — Service without selector, port 5432" $d "Service db-ext missing from $NS"
fi
if [ "$(ep_count $NS db-ext)" -ge 1 ]; then
  pass 3 "A4b db-ext — manual Endpoints filled in (≥1 address)" $d
else
  fail 3 "A4b db-ext — create the Endpoints object db-ext (IP of legacy-db:5432)" $d "no Endpoints address for db-ext"
fi
cip=$(kubectl -n $NS get svc db-ext -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$cip" ] && probe_connect "$cip:5432"; then
  pass 2 "A4c db-ext — traffic routed through to legacy-db:5432" $d
else
  fail 2 "A4c db-ext — connection clusterIP:5432 reaches legacy-db" $d "connection refused/timeout (Endpoints IP or port ?)"
fi

# ── A5 — Fix shop-svc (endpoints 3 + connect 3) ──
if [ "$(ep_count $NS shop-svc)" -ge 1 ]; then
  pass 3 "A5a shop-svc — populated endpoints (selector + targetPort fixed)" $d
else
  fail 3 "A5a shop-svc — fix selector/targetPort to populate the endpoints" $d "empty endpoints (selector=app=shop ? targetPort=80 ?)"
fi
cip=$(kubectl -n $NS get svc shop-svc -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$cip" ] && probe_connect "$cip:80"; then
  pass 3 "A5b shop-svc — reachable on :80" $d
else
  fail 3 "A5b shop-svc — connection clusterIP:80 OK" $d "connection refused/timeout (Service still broken)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom ING 30 "🌐 Ingress"
d=ING
NS=ingress-lab

# ── B1 — Ingress site (class+host 4 + path/backend 6) ──
if kubectl -n $NS get ingress site >/dev/null 2>&1; then
  icn=$(kubectl -n $NS get ingress site -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
  ho=$(kubectl -n $NS get ingress site -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  if [ "$icn" = "lab-nginx" ] && [ "$ho" = "web.cka.local" ]; then
    pass 4 "B1a site — ingressClassName lab-nginx, host web.cka.local" $d
  else
    r=""
    [ "$icn" = "lab-nginx" ]     || r+="ingressClassName=${icn:-absent}(≠lab-nginx); "
    [ "$ho" = "web.cka.local" ]  || r+="host=${ho:-absent}(≠web.cka.local); "
    fail 4 "B1a site — class lab-nginx + host web.cka.local" $d "${r%; }"
  fi
  trip=$(kubectl -n $NS get ingress site -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path}|{.pathType}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$trip" | grep -qx '/|Prefix|web-svc:80'; then
    pass 6 "B1b site — / (Prefix) → web-svc:80" $d
  else
    fail 6 "B1b site — path / Prefix to web-svc:80" $d "paths found = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
else
  fail 4 "B1a site — class lab-nginx + host web.cka.local" $d "Ingress site missing from $NS"
  fail 6 "B1b site — / (Prefix) → web-svc:80" $d "Ingress site missing"
fi

# ── B2 — Ingress fanout apps (class+host 2 + /app 4 + /api 4) ──
if kubectl -n $NS get ingress apps >/dev/null 2>&1; then
  icn=$(kubectl -n $NS get ingress apps -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
  ho=$(kubectl -n $NS get ingress apps -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  if [ "$icn" = "lab-nginx" ] && [ "$ho" = "apps.cka.local" ]; then
    pass 2 "B2a apps — ingressClassName lab-nginx, host apps.cka.local" $d
  else
    r=""
    [ "$icn" = "lab-nginx" ]      || r+="ingressClassName=${icn:-absent}(≠lab-nginx); "
    [ "$ho" = "apps.cka.local" ]  || r+="host=${ho:-absent}(≠apps.cka.local); "
    fail 2 "B2a apps — class lab-nginx + host apps.cka.local" $d "${r%; }"
  fi
  trip=$(kubectl -n $NS get ingress apps -o jsonpath='{range .spec.rules[*].http.paths[*]}{.path}|{.pathType}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' 2>/dev/null)
  # Prefix pathType ignores a trailing slash: /app/ ≡ /app (Ingress spec).
  if printf '%s' "$trip" | grep -qxE '/app/?\|Prefix\|app-svc:80'; then
    pass 4 "B2b apps — /app (Prefix) → app-svc:80" $d
  else
    fail 4 "B2b apps — /app Prefix to app-svc:80" $d "paths = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
  if printf '%s' "$trip" | grep -qxE '/api/?\|Prefix\|api-svc:80'; then
    pass 4 "B2c apps — /api (Prefix) → api-svc:80" $d
  else
    fail 4 "B2c apps — /api Prefix to api-svc:80" $d "paths = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
else
  fail 2 "B2a apps — class lab-nginx + host apps.cka.local" $d "Ingress apps missing from $NS"
  fail 4 "B2b apps — /app → app-svc:80" $d "Ingress apps missing"
  fail 4 "B2c apps — /api → api-svc:80" $d "Ingress apps missing"
fi

# ── B3 — Ingress TLS secure (secret 3 + tls 4 + backend 3) ──
sty=$(kubectl -n $NS get secret secure-tls -o jsonpath='{.type}' 2>/dev/null)
if [ "$sty" = "kubernetes.io/tls" ]; then
  pass 3 "B3a secure-tls — Secret of type kubernetes.io/tls present" $d
else
  fail 3 "B3a secure-tls — Secret TLS (kubectl create secret tls)" $d "type=${sty:-absent}(≠kubernetes.io/tls)"
fi
if kubectl -n $NS get ingress secure >/dev/null 2>&1; then
  icn=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
  tsec=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)
  thost=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null)
  if [ "$icn" = "lab-nginx" ] && [ "$tsec" = "secure-tls" ] && [ "$thost" = "secure.cka.local" ]; then
    pass 4 "B3b secure — class lab-nginx + tls block (secretName secure-tls, host secure.cka.local)" $d
  else
    r=""
    [ "$icn" = "lab-nginx" ]          || r+="ingressClassName=${icn:-absent}(≠lab-nginx); "
    [ "$tsec" = "secure-tls" ]        || r+="tls.secretName=${tsec:-absent}(≠secure-tls); "
    [ "$thost" = "secure.cka.local" ] || r+="tls.hosts[0]=${thost:-absent}(≠secure.cka.local); "
    fail 4 "B3b secure — class lab-nginx + tls block secretName+host" $d "${r%; }"
  fi
  rho=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  trip=$(kubectl -n $NS get ingress secure -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' 2>/dev/null)
  if [ "$rho" = "secure.cka.local" ] && printf '%s' "$trip" | grep -qx '/|web-svc:80'; then
    pass 3 "B3c secure — rule host secure.cka.local, / → web-svc:80" $d
  else
    fail 3 "B3c secure — rule host + / to web-svc:80" $d "host=${rho:-absent} ; paths = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
else
  fail 4 "B3b secure — class lab-nginx + tls block secretName+host" $d "Ingress secure missing from $NS"
  fail 3 "B3c secure — rule host + backend" $d "Ingress secure missing"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom GW 30 "🚪 Gateway API"
d=GW
NS=gateway-lab

# ── C1 — HTTPRoute main-route (parentRefs 2 + /web 4 + /api 4) ──
if kubectl -n $NS get httproute main-route >/dev/null 2>&1; then
  pr=$(kubectl -n $NS get httproute main-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$pr" | grep -qw edge; then
    pass 2 "C1a main-route — attached to the Gateway edge (parentRefs)" $d
  else
    fail 2 "C1a main-route — parentRefs to edge" $d "parentRefs=${pr:-empty}"
  fi
  pb=$(kubectl -n $NS get httproute main-route -o jsonpath='{range .spec.rules[*]}{.matches[0].path.value}|{.backendRefs[0].name}:{.backendRefs[0].port}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$pb" | grep -qx '/web|web-svc:80'; then
    pass 4 "C1b main-route — /web → web-svc:80" $d
  else
    fail 4 "C1b main-route — prefix /web to web-svc:80" $d "rules = $(printf '%s' "$pb" | tr '\n' ' ')"
  fi
  if printf '%s' "$pb" | grep -qx '/api|api-svc:80'; then
    pass 4 "C1c main-route — /api → api-svc:80" $d
  else
    fail 4 "C1c main-route — prefix /api to api-svc:80" $d "rules = $(printf '%s' "$pb" | tr '\n' ' ')"
  fi
else
  fail 2 "C1a main-route — parentRefs to edge" $d "HTTPRoute main-route missing from $NS"
  fail 4 "C1b main-route — /web → web-svc:80" $d "HTTPRoute missing"
  fail 4 "C1c main-route — /api → api-svc:80" $d "HTTPRoute missing"
fi

# ── C2 — HTTPRoute tier-route : header X-Tier + catch-all (parentRefs 2 + gold 4 + std 4) ──
if kubectl -n $NS get httproute tier-route >/dev/null 2>&1; then
  pr=$(kubectl -n $NS get httproute tier-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$pr" | grep -qw edge; then
    pass 2 "C2a tier-route — attached to the Gateway edge" $d
  else
    fail 2 "C2a tier-route — parentRefs to edge" $d "parentRefs=${pr:-empty}"
  fi
  # per rule: path | header=name=value | backend
  ph=$(kubectl -n $NS get httproute tier-route -o jsonpath='{range .spec.rules[*]}{.matches[0].path.value}|{.matches[0].headers[0].name}={.matches[0].headers[0].value}|{.backendRefs[0].name}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$ph" | grep -qix '/shop|X-Tier=gold|gold-svc'; then
    pass 4 "C2b tier-route — /shop + header X-Tier: gold (same match) → gold-svc" $d
  else
    fail 4 "C2b tier-route — /shop conditioned on X-Tier: gold to gold-svc" $d "rules (path|header|backend) = $(printf '%s' "$ph" | tr '\n' ' ')"
  fi
  if printf '%s' "$ph" | grep -qx '/shop|=|std-svc'; then
    pass 4 "C2c tier-route — catch-all /shop (without header) → std-svc" $d
  else
    fail 4 "C2c tier-route — /shop catch-all to std-svc" $d "no /shop rule without header to std-svc"
  fi
else
  fail 2 "C2a tier-route — parentRefs to edge" $d "HTTPRoute tier-route missing from $NS"
  fail 4 "C2b tier-route — /shop + X-Tier: gold → gold-svc" $d "HTTPRoute missing"
  fail 4 "C2c tier-route — catch-all /shop → std-svc" $d "HTTPRoute missing"
fi

# ── C3 — HTTPRoute canary-route : weighted split (parentRefs 2 + v1 90 % 4 + v2 10 % 4) ──
if kubectl -n $NS get httproute canary-route >/dev/null 2>&1; then
  pr=$(kubectl -n $NS get httproute canary-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$pr" | grep -qw edge; then
    pass 2 "C3a canary-route — attached to the Gateway edge" $d
  else
    fail 2 "C3a canary-route — parentRefs to edge" $d "parentRefs=${pr:-empty}"
  fi
  w1=$(kubectl -n $NS get httproute canary-route -o jsonpath='{.spec.rules[0].backendRefs[?(@.name=="canary-v1")].weight}' 2>/dev/null)
  w2=$(kubectl -n $NS get httproute canary-route -o jsonpath='{.spec.rules[0].backendRefs[?(@.name=="canary-v2")].weight}' 2>/dev/null)
  if [ "$w1" = "90" ]; then
    pass 4 "C3b canary-route — canary-v1 weight 90" $d
  else
    fail 4 "C3b canary-route — backendRef canary-v1 weight 90" $d "weight(canary-v1)=${w1:-absent}"
  fi
  if [ "$w2" = "10" ]; then
    pass 4 "C3c canary-route — canary-v2 weight 10" $d
  else
    fail 4 "C3c canary-route — backendRef canary-v2 weight 10" $d "weight(canary-v2)=${w2:-absent}"
  fi
else
  fail 2 "C3a canary-route — parentRefs to edge" $d "HTTPRoute canary-route missing from $NS"
  fail 4 "C3b canary-route — canary-v1 weight 90" $d "HTTPRoute missing"
  fail 4 "C3c canary-route — canary-v2 weight 10" $d "HTTPRoute missing"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
TOTAL=0; GOT=0
printf "\n────────────────────────────────────────────────────────\n"
printf "Subtotal per domain:\n"
declare -A DOM_LABEL=( [SVC]="Services" [ING]="Ingress" [GW]="Gateway API" )
for k in SVC ING GW; do
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
