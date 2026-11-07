#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose.yml")

"${COMPOSE[@]}" stop legacy-edge

echo
echo "The legacy edge is stopped. The controller is reachable only from the OT network."
echo "The dashboard's legacy mode should show 'Path unavailable'."
echo "Switch to Mesh mode to keep the same freezer view over the Macula gateway."
echo "Confirm the closed path: $ROOT/scripts/scan-after-retrofit.sh"
