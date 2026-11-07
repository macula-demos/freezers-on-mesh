#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose.yml")

"${COMPOSE[@]}" exec -T freezer-controller curl -fsS -u admin:admin \
  -X POST http://localhost:8080/api/reset | jq .

echo "Lab reset to safe temperatures."
