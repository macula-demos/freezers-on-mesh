#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose.yml")

echo "Building and starting the as-is lab..."
"${COMPOSE[@]}" up -d --build freezer-controller legacy-edge attacker admin-ui

# The controller may have been recreated with a new address on ot_net.
# nginx resolves the upstream name at startup, so refresh the edge too.
"${COMPOSE[@]}" restart legacy-edge

echo "Waiting for the controller through the legacy edge..."
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "Waiting for the admin UI..."
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:4000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

"$ROOT/scripts/scan.sh"

echo
echo "Admin UI:      http://localhost:4000"
echo "Run the attack: $ROOT/scripts/attack.sh"
echo "Reset the lab:  $ROOT/scripts/reset.sh"
echo "Retrofit:       $ROOT/scripts/stop-legacy-edge.sh"
