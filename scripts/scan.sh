#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose.yml")

echo "== Port scan: the shop edge =="
"${COMPOSE[@]}" exec -T attacker nmap -sT -Pn -p 80,443 legacy-edge

echo
echo "== HTTP response from the exposed edge =="
"${COMPOSE[@]}" exec -T attacker curl -sS -D - -o /dev/null http://legacy-edge/ || true

echo
echo "== Unauthenticated read: no credentials required =="
"${COMPOSE[@]}" exec -T attacker curl -sS http://legacy-edge/api/freezers |
  jq '{freezers: [.freezers[] | {id, name, current_c, target_c, alarm}]}'
