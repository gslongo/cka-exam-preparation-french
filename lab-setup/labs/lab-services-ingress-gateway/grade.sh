#!/usr/bin/env bash
# grade.sh — correction automatique du lab « Services · Ingress · Gateway API ».
# À lancer SUR cp1 :  vagrant ssh cp1 -c "bash /vagrant/labs/lab-services-ingress-gateway/grade.sh"
#
# N'effectue AUCUNE modification : lecture seule. Affiche PASS/FAIL par tâche
# (avec le symptôme observé en cas d'échec, mais JAMAIS la solution),
# sous-total par domaine et score total. Objectif ≥ 75 %.
set -uo pipefail

SCORE=0
declare -A DOM_GOT DOM_MAX

pass() { SCORE=$((SCORE+$1)); DOM_GOT[$3]=$(( ${DOM_GOT[$3]:-0} + $1 )); printf "   \033[32m✅ +%-2d\033[0m %s\n" "$1" "$2"; }
fail() { printf "   \033[31m❌  0 \033[0m %s\n" "$2"; [ -n "${4:-}" ] && printf "         \033[2m↳ %s\033[0m\n" "$4"; }
dom()  { DOM_MAX[$1]=$2; printf "\n\033[1m%s (%d pts)\033[0m\n" "$3" "$2"; }

# Nombre d'adresses d'Endpoints d'un Service (ns, name)
ep_count() { kubectl -n "$1" get endpoints "$2" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w; }
# Connexion TCP depuis le Pod probe vers <clusterIP:port> (via agnhost)
probe_connect() { kubectl -n services-lab exec probe -- /agnhost connect "$1" --timeout=3s >/dev/null 2>&1; }

# ══════════════════════════════════════════════════════════════════════════════
dom SVC 40 "🔌 Services"
d=SVC
NS=services-lab

# ── A1 — ClusterIP web-svc (spec 5 + endpoints/connectivité 5) ──
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
  pass 5 "A1b web-svc — 2 endpoints prêts et joignable sur :80" $d
else
  fail 5 "A1b web-svc — endpoints peuplés + connexion :80 OK" $d \
    "endpoints=$(ep_count $NS web-svc) (attendu ≥2) ou connexion clusterIP:80 refusée (selector/targetPort ?)"
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
  fail 5 "A2a web-np — NodePort sur 30080" $d "${r%; }"
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
  [ "$ci" = "None" ]  || r+="clusterIP=${ci:-absent}(≠None → pas headless); "
  [ "$se" = "cache" ] || r+="selector.app=${se:-absent}(≠cache); "
  [ "$po" = "80" ]    || r+="port=${po:-absent}(≠80); "
  fail 5 "A3a cache-hl — headless selector app=cache port 80" $d "${r%; }"
fi
if [ "$(ep_count $NS cache-hl)" -ge 2 ]; then
  pass 3 "A3b cache-hl — 2 adresses de Pods dans les endpoints" $d
else
  fail 3 "A3b cache-hl — endpoints listent les IP des Pods cache" $d "endpoints=$(ep_count $NS cache-hl) (attendu ≥2)"
fi

# ── A4 — Service SANS selector + Endpoints manuels (svc 3 + ep 3 + connect 2) ──
if kubectl -n $NS get svc db-ext >/dev/null 2>&1; then
  se=$(kubectl -n $NS get svc db-ext -o jsonpath='{.spec.selector}' 2>/dev/null)
  po=$(kubectl -n $NS get svc db-ext -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  if [ -z "$se" ] && [ "$po" = "5432" ]; then
    pass 3 "A4a db-ext — Service sans selector, port 5432" $d
  else
    r=""
    [ -z "$se" ]        || r+="un selector est défini (doit être absent); "
    [ "$po" = "5432" ]  || r+="port=${po:-absent}(≠5432); "
    fail 3 "A4a db-ext — Service sans selector, port 5432" $d "${r%; }"
  fi
else
  fail 3 "A4a db-ext — Service sans selector, port 5432" $d "Service db-ext absent de $NS"
fi
if [ "$(ep_count $NS db-ext)" -ge 1 ]; then
  pass 3 "A4b db-ext — Endpoints manuels renseignés (≥1 adresse)" $d
else
  fail 3 "A4b db-ext — créer l'objet Endpoints db-ext (IP de legacy-db:5432)" $d "aucune adresse d'Endpoints pour db-ext"
fi
cip=$(kubectl -n $NS get svc db-ext -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$cip" ] && probe_connect "$cip:5432"; then
  pass 2 "A4c db-ext — trafic routé jusqu'à legacy-db:5432" $d
else
  fail 2 "A4c db-ext — connexion clusterIP:5432 aboutit à legacy-db" $d "connexion refusée/timeout (IP ou port des Endpoints ?)"
fi

# ── A5 — Réparer shop-svc (endpoints 3 + connect 3) ──
if [ "$(ep_count $NS shop-svc)" -ge 1 ]; then
  pass 3 "A5a shop-svc — endpoints peuplés (selector + targetPort corrigés)" $d
else
  fail 3 "A5a shop-svc — corriger selector/targetPort pour peupler les endpoints" $d "endpoints vides (selector=app=shop ? targetPort=80 ?)"
fi
cip=$(kubectl -n $NS get svc shop-svc -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$cip" ] && probe_connect "$cip:80"; then
  pass 3 "A5b shop-svc — joignable sur :80" $d
else
  fail 3 "A5b shop-svc — connexion clusterIP:80 OK" $d "connexion refusée/timeout (Service toujours cassé)"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom ING 30 "🌐 Ingress"
d=ING
NS=ingress-lab

# ── B1 — Ingress site (classe+host 4 + chemin/backend 6) ──
if kubectl -n $NS get ingress site >/dev/null 2>&1; then
  icn=$(kubectl -n $NS get ingress site -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
  ho=$(kubectl -n $NS get ingress site -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  if [ "$icn" = "lab-nginx" ] && [ "$ho" = "web.cka.local" ]; then
    pass 4 "B1a site — ingressClassName lab-nginx, host web.cka.local" $d
  else
    r=""
    [ "$icn" = "lab-nginx" ]     || r+="ingressClassName=${icn:-absent}(≠lab-nginx); "
    [ "$ho" = "web.cka.local" ]  || r+="host=${ho:-absent}(≠web.cka.local); "
    fail 4 "B1a site — classe lab-nginx + host web.cka.local" $d "${r%; }"
  fi
  trip=$(kubectl -n $NS get ingress site -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path}|{.pathType}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$trip" | grep -qx '/|Prefix|web-svc:80'; then
    pass 6 "B1b site — / (Prefix) → web-svc:80" $d
  else
    fail 6 "B1b site — chemin / Prefix vers web-svc:80" $d "chemins trouvés = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
else
  fail 4 "B1a site — classe lab-nginx + host web.cka.local" $d "Ingress site absent de $NS"
  fail 6 "B1b site — / (Prefix) → web-svc:80" $d "Ingress site absent"
fi

# ── B2 — Ingress fanout apps (host 2 + /app 4 + /api 4) ──
if kubectl -n $NS get ingress apps >/dev/null 2>&1; then
  ho=$(kubectl -n $NS get ingress apps -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  if [ "$ho" = "apps.cka.local" ]; then
    pass 2 "B2a apps — host apps.cka.local" $d
  else
    fail 2 "B2a apps — host apps.cka.local" $d "host=${ho:-absent}"
  fi
  trip=$(kubectl -n $NS get ingress apps -o jsonpath='{range .spec.rules[*].http.paths[*]}{.path}|{.pathType}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$trip" | grep -qx '/app|Prefix|app-svc:80'; then
    pass 4 "B2b apps — /app (Prefix) → app-svc:80" $d
  else
    fail 4 "B2b apps — /app Prefix vers app-svc:80" $d "chemins = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
  if printf '%s' "$trip" | grep -qx '/api|Prefix|api-svc:80'; then
    pass 4 "B2c apps — /api (Prefix) → api-svc:80" $d
  else
    fail 4 "B2c apps — /api Prefix vers api-svc:80" $d "chemins = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
else
  fail 2 "B2a apps — host apps.cka.local" $d "Ingress apps absent de $NS"
  fail 4 "B2b apps — /app → app-svc:80" $d "Ingress apps absent"
  fail 4 "B2c apps — /api → api-svc:80" $d "Ingress apps absent"
fi

# ── B3 — Ingress TLS secure (secret 3 + tls 4 + backend 3) ──
sty=$(kubectl -n $NS get secret secure-tls -o jsonpath='{.type}' 2>/dev/null)
if [ "$sty" = "kubernetes.io/tls" ]; then
  pass 3 "B3a secure-tls — Secret de type kubernetes.io/tls présent" $d
else
  fail 3 "B3a secure-tls — Secret TLS (kubectl create secret tls)" $d "type=${sty:-absent}(≠kubernetes.io/tls)"
fi
if kubectl -n $NS get ingress secure >/dev/null 2>&1; then
  tsec=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)
  thost=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null)
  if [ "$tsec" = "secure-tls" ] && [ "$thost" = "secure.cka.local" ]; then
    pass 4 "B3b secure — bloc tls (secretName secure-tls, host secure.cka.local)" $d
  else
    r=""
    [ "$tsec" = "secure-tls" ]        || r+="tls.secretName=${tsec:-absent}(≠secure-tls); "
    [ "$thost" = "secure.cka.local" ] || r+="tls.hosts[0]=${thost:-absent}(≠secure.cka.local); "
    fail 4 "B3b secure — bloc tls secretName+host" $d "${r%; }"
  fi
  rho=$(kubectl -n $NS get ingress secure -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
  trip=$(kubectl -n $NS get ingress secure -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path}|{.backend.service.name}:{.backend.service.port.number}{"\n"}{end}' 2>/dev/null)
  if [ "$rho" = "secure.cka.local" ] && printf '%s' "$trip" | grep -qx '/|web-svc:80'; then
    pass 3 "B3c secure — règle host secure.cka.local, / → web-svc:80" $d
  else
    fail 3 "B3c secure — règle host + / vers web-svc:80" $d "host=${rho:-absent} ; chemins = $(printf '%s' "$trip" | tr '\n' ' ')"
  fi
else
  fail 4 "B3b secure — bloc tls secretName+host" $d "Ingress secure absent de $NS"
  fail 3 "B3c secure — règle host + backend" $d "Ingress secure absent"
fi

# ══════════════════════════════════════════════════════════════════════════════
dom GW 30 "🚪 Gateway API"
d=GW
NS=gateway-lab

# ── C1 — HTTPRoute main-route (parentRefs 2 + /web 4 + /api 4) ──
if kubectl -n $NS get httproute main-route >/dev/null 2>&1; then
  pr=$(kubectl -n $NS get httproute main-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$pr" | grep -qw edge; then
    pass 2 "C1a main-route — rattachée au Gateway edge (parentRefs)" $d
  else
    fail 2 "C1a main-route — parentRefs vers edge" $d "parentRefs=${pr:-vide}"
  fi
  pb=$(kubectl -n $NS get httproute main-route -o jsonpath='{range .spec.rules[*]}{.matches[0].path.value}|{.backendRefs[0].name}:{.backendRefs[0].port}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$pb" | grep -qx '/web|web-svc:80'; then
    pass 4 "C1b main-route — /web → web-svc:80" $d
  else
    fail 4 "C1b main-route — préfixe /web vers web-svc:80" $d "règles = $(printf '%s' "$pb" | tr '\n' ' ')"
  fi
  if printf '%s' "$pb" | grep -qx '/api|api-svc:80'; then
    pass 4 "C1c main-route — /api → api-svc:80" $d
  else
    fail 4 "C1c main-route — préfixe /api vers api-svc:80" $d "règles = $(printf '%s' "$pb" | tr '\n' ' ')"
  fi
else
  fail 2 "C1a main-route — parentRefs vers edge" $d "HTTPRoute main-route absente de $NS"
  fail 4 "C1b main-route — /web → web-svc:80" $d "HTTPRoute absente"
  fail 4 "C1c main-route — /api → api-svc:80" $d "HTTPRoute absente"
fi

# ── C2 — HTTPRoute tier-route : header X-Tier + catch-all (parentRefs 2 + gold 4 + std 4) ──
if kubectl -n $NS get httproute tier-route >/dev/null 2>&1; then
  pr=$(kubectl -n $NS get httproute tier-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$pr" | grep -qw edge; then
    pass 2 "C2a tier-route — rattachée au Gateway edge" $d
  else
    fail 2 "C2a tier-route — parentRefs vers edge" $d "parentRefs=${pr:-vide}"
  fi
  # par règle : path | header=nom=valeur | backend
  ph=$(kubectl -n $NS get httproute tier-route -o jsonpath='{range .spec.rules[*]}{.matches[0].path.value}|{.matches[0].headers[0].name}={.matches[0].headers[0].value}|{.backendRefs[0].name}{"\n"}{end}' 2>/dev/null)
  if printf '%s' "$ph" | grep -qix '/shop|X-Tier=gold|gold-svc'; then
    pass 4 "C2b tier-route — /shop + en-tête X-Tier: gold (même match) → gold-svc" $d
  else
    fail 4 "C2b tier-route — /shop conditionné par X-Tier: gold vers gold-svc" $d "règles (path|header|backend) = $(printf '%s' "$ph" | tr '\n' ' ')"
  fi
  if printf '%s' "$ph" | grep -qx '/shop|=|std-svc'; then
    pass 4 "C2c tier-route — catch-all /shop (sans en-tête) → std-svc" $d
  else
    fail 4 "C2c tier-route — /shop catch-all vers std-svc" $d "aucune règle /shop sans en-tête vers std-svc"
  fi
else
  fail 2 "C2a tier-route — parentRefs vers edge" $d "HTTPRoute tier-route absente de $NS"
  fail 4 "C2b tier-route — /shop + X-Tier: gold → gold-svc" $d "HTTPRoute absente"
  fail 4 "C2c tier-route — catch-all /shop → std-svc" $d "HTTPRoute absente"
fi

# ── C3 — HTTPRoute canary-route : répartition pondérée (parentRefs 2 + v1 90 % 4 + v2 10 % 4) ──
if kubectl -n $NS get httproute canary-route >/dev/null 2>&1; then
  pr=$(kubectl -n $NS get httproute canary-route -o jsonpath='{.spec.parentRefs[*].name}' 2>/dev/null)
  if printf '%s' "$pr" | grep -qw edge; then
    pass 2 "C3a canary-route — rattachée au Gateway edge" $d
  else
    fail 2 "C3a canary-route — parentRefs vers edge" $d "parentRefs=${pr:-vide}"
  fi
  w1=$(kubectl -n $NS get httproute canary-route -o jsonpath='{.spec.rules[0].backendRefs[?(@.name=="canary-v1")].weight}' 2>/dev/null)
  w2=$(kubectl -n $NS get httproute canary-route -o jsonpath='{.spec.rules[0].backendRefs[?(@.name=="canary-v2")].weight}' 2>/dev/null)
  if [ "$w1" = "90" ]; then
    pass 4 "C3b canary-route — canary-v1 poids 90" $d
  else
    fail 4 "C3b canary-route — backendRef canary-v1 weight 90" $d "weight(canary-v1)=${w1:-absent}"
  fi
  if [ "$w2" = "10" ]; then
    pass 4 "C3c canary-route — canary-v2 poids 10" $d
  else
    fail 4 "C3c canary-route — backendRef canary-v2 weight 10" $d "weight(canary-v2)=${w2:-absent}"
  fi
else
  fail 2 "C3a canary-route — parentRefs vers edge" $d "HTTPRoute canary-route absente de $NS"
  fail 4 "C3b canary-route — canary-v1 poids 90" $d "HTTPRoute absente"
  fail 4 "C3c canary-route — canary-v2 poids 10" $d "HTTPRoute absente"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Récapitulatif
TOTAL=0; GOT=0
printf "\n────────────────────────────────────────────────────────\n"
printf "Sous-totaux par domaine :\n"
declare -A DOM_LABEL=( [SVC]="Services" [ING]="Ingress" [GW]="Gateway API" )
for k in SVC ING GW; do
  [ -n "${DOM_MAX[$k]:-}" ] || continue
  printf "  %-24s %2d / %d\n" "${DOM_LABEL[$k]}" "${DOM_GOT[$k]:-0}" "${DOM_MAX[$k]}"
  TOTAL=$((TOTAL + DOM_MAX[$k])); GOT=$((GOT + ${DOM_GOT[$k]:-0}))
done
printf "────────────────────────────────────────────────────────\n"
printf "SCORE TOTAL : %d / %d\n" "$GOT" "$TOTAL"
if [ "$TOTAL" -gt 0 ] && [ $((GOT*100/TOTAL)) -ge 75 ]; then
  printf "\033[32m🎉 OBJECTIF ATTEINT (≥ 75%%)\033[0m\n"
else
  printf "\033[31mÀ RETRAVAILLER (< 75%%)\033[0m\n"
fi
printf "────────────────────────────────────────────────────────\n"
