#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose.yml")

# The attacker is on the simulated internet network only. After the retrofit it
# has no route to the OT network, so these probes should find nothing.
run_attacker() {
  "${COMPOSE[@]}" exec -T attacker "$@" || true
}

check_resolution() {
  if "${COMPOSE[@]}" exec -T attacker getent hosts "$1" 2>/dev/null; then
    :
  else
    echo "$1 did not resolve"
  fi
}

attacker_id=$("${COMPOSE[@]}" ps -q attacker)
internet_net=$(docker inspect \
  -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' \
  "$attacker_id" | awk '/_internet_net$/{print; exit}')
internet_gw=$(docker network inspect "$internet_net" \
  -f '{{(index .IPAM.Config 0).Gateway}}')

controller_id=$("${COMPOSE[@]}" ps -q freezer-controller)
controller_ip=$(docker inspect \
  -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  "$controller_id")

echo "== Port scan: the old shop edge on the host gateway =="
echo "Target: $internet_gw (the edge's published 8080/8443 plus common HTTP ports)"
run_attacker nmap -sT -Pn -p 80,443,8080,8443 "$internet_gw"

echo
echo "== Port scan: the controller's OT address from the simulated internet =="
echo "Target: $controller_ip (the controller is on the OT network only)"
run_attacker nmap -sT -Pn -p 80,443,8080,502 "$controller_ip"

echo
echo "== Name resolution from the attacker =="
check_resolution legacy-edge
check_resolution freezer-controller

echo
echo "== Direct HTTP probes =="
run_attacker sh -c '
  if curl -sS --max-time 3 http://legacy-edge/api/freezers >/dev/null 2>&1; then
    echo "legacy edge answered (unexpected)"
  else
    echo "legacy edge: no answer"
  fi
'
run_attacker sh -c '
  if curl -sS --max-time 3 http://freezer-controller:8080/api/freezers >/dev/null 2>&1; then
    echo "controller answered (unexpected)"
  else
    echo "controller: no answer"
  fi
'

echo
echo "No controller ports are reachable from the simulated internet."
