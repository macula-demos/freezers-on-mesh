# Demo script

Two halves: the as-is attack, and the mesh path that replaces the exposed port forward with an
outbound-only gateway. The mesh half covers reads, authorized writes, and the replay and stranger
refusals.

A captioned recording of this run is in [assets/demo.mp4](../assets/demo.mp4).

## Preconditions

- Docker with Compose.
- Ports `4000` (dashboard), `8080`/`8443` (legacy edge), and `4433/udp` (the local station, inside
  the Compose network) are free.
- The first `mesh-demo.sh` run pulls the station image and builds the gateway, realm fixture, and
  dashboard. Later runs reuse the build cache.

## A. Start the full lab

```bash
./scripts/mesh-demo.sh
```

The script starts the station, records its node id, starts the realm fixture (which publishes the
D25 chain and writes `deploy/generated/realm.json`), starts the gateway, and waits for the UI. It
prints the realm, the gateway's `/health`, and the dashboard URL.

Open <http://localhost:4000>. The dashboard starts in **Legacy** mode.

## 1. Scan the shop edge

The scan is part of `demo.sh`; with the full lab already up, run:

```bash
./scripts/scan.sh
```

Expected:

```text
PORT    STATE SERVICE
80/tcp  open  http
443/tcp open  https
```

The unauthenticated read returns four freezers. No credentials are needed.

## 2. Take control with the default credentials

```bash
./scripts/attack.sh
```

Expected:

- FZ-01's target becomes `+50°C`.
- FZ-01 enters `defrost` and climbs out of its safe band.
- The controller audit shows `admin`, the attacker's source address, `set_target`, and
  `start_defrost`.

After about ten seconds the dashboard shows **at risk** and the sparkline turns amber or red. The
same actions are available from the **Attacker view** panel.

## 3. The retrofit moment

```bash
./scripts/stop-legacy-edge.sh
```

Expected:

- The published `8080`/`8443` ports stop answering.
- The dashboard's legacy mode shows **Path unavailable**.
- The controller keeps running, but it is reachable only from the OT network.

Confirm the reduction from the simulated internet:

```bash
./scripts/scan-after-retrofit.sh
```

Expected: the old edge has no open ports, `freezer-controller` does not resolve or answer, and both
direct HTTP probes fail. Before the retrofit the same attacker network found the edge and read the
freezer list without credentials.

## 4. Switch to the mesh path

Click **Mesh** in the dashboard's mode switch. The button is enabled once the local MeshClient has
connected to the station; if it is still disabled, wait a second and try again.

Expected:

- The header changes to **Mesh path**.
- The posture cards say **no inbound port**, **operator node**, and **caller + command id**.
- The freezer cards keep updating with the same controller data.
- The **Mesh path** card shows local UI → station → gateway, the open read policy, the operator-only
  write policy, and the operator's short node id.
- The **Last call** line says **sealed**, with the gateway's provider node id and the seal key id.

The controller never moved. The network path did.

## 5. Write through the gateway

In Mesh mode the freezer controls are enabled once the Mesh client has connected, with no login.
The gateway authorizes the write by the operator node identity, not by a shared password.

1. Click a preset on FZ-01, for example **+50**.

   Expected:

   - The flash says **Gateway accepted FZ-01 target 50.0°C (sealed).**
   - The **Gateway audit** table gains a row with the operator's node id (the short id shown in the
     Mesh card; yours will differ), action `set_target`, freezer `FZ-01`, a command id, and result
     `ok`.
   - The controller's own audit shows `"user": "gateway"`, not `admin`.

2. Click **Replay last command (should be refused)**.

   Expected: **Command refused: command_replayed (the gateway already saw this command id)**, and a
   second gateway audit row with the same command id and result `command_replayed`.

3. Click **Try as stranger (should be refused)**.

   Expected: **Stranger &lt;node-id&gt; refused: unauthorized (this node is not on the gateway's
   operator list)**. The stranger is a second node identity generated at `/data/stranger.key`; it is
   a different node id from the operator. The gateway refuses it before the command handler runs, so
   this attempt does not produce a gateway audit row.

Why this works:

- The write capabilities (and `ot/list_freezer_commands`) are advertised with
  `{callers, {nodes, [OperatorNodeId]}}`. Only the operator's node is offered the procedures.
- The operator id comes from `/mesh/operator-node-id`, which the dashboard writes on connect. The
  gateway entrypoint exports it as `OPERATOR_NODE_IDS`; without it the gateway advertises no write
  capabilities.
- Every write carries a random command id and a timestamp. The guard remembers accepted ids for two
  minutes, so the replay is refused as `command_replayed` (stale commands are `command_expired`).
- The gateway calls the controller with its own strong `gateway` account. The dashboard never holds
  that credential, and the browser never holds the operator key.

## 6. Reset

```bash
./scripts/reset.sh
```

The script reaches the controller from inside its own container, so it works whether or not the
legacy edge is running. It resets every freezer to its initial target and current temperature.

To bring the legacy edge back for another run:

```bash
docker compose -f deploy/compose.yml start legacy-edge
```

## Troubleshooting

- **The dashboard shows "Path unavailable" in Legacy mode.** The `legacy-edge` is stopped or still
  starting. This is expected after the retrofit; switch to Mesh.
- **The Mesh button is disabled.** The local MeshClient has not connected to the station. Check
  `docker compose -f deploy/compose.yml logs --tail=50 admin-ui` for `mesh client connected`, and
  check that the station, realm fixture, and gateway are up.
- **The mesh call returns `no_provider` or `unresolved`.** The gateway has not advertised yet, or
  the realm fixture has not published the D25 chain. Check the gateway's `/health`:

  ```bash
  docker compose -f deploy/compose.yml exec -T ot-gateway \
    curl -sS --unix-socket /run/mcl/health.sock http://localhost/health | jq .
  ```

  `claim.state` should be `issued`, and `provider_grants` should include `ot/list_freezers`,
  `ot/set_freezer_target`, `ot/start_freezer_defrost`, `ot/stop_freezer_defrost`, and
  `ot/list_freezer_commands`.
- **A Mesh write returns `unauthorized`.** The gateway was started before the dashboard wrote
  `/mesh/operator-node-id`, or the operator key changed (for example the `/data` volume was wiped).
  Check the operator id and restart the gateway so its entrypoint re-reads the file:

  ```bash
  cat deploy/generated/operator-node-id
  docker compose -f deploy/compose.yml up -d --force-recreate --no-deps ot-gateway
  ```
- **Replay returns `no_last_command`.** Issue a write in Mesh mode first; the probe re-sends the last
  command this process accepted.
- **Replay returns `command_expired` instead of `command_replayed`.** More than two minutes passed
  between the write and the replay. Issue a fresh write and replay immediately.
- **The stranger write is accepted.** The gateway is not enforcing the operator policy. Check that
  `OPERATOR_NODE_IDS` is set from `/mesh/operator-node-id` and that the gateway logs list the write
  capabilities under `{nodes, ...}`.
- **The station is crash-looping with `no_tiers`.** Its bootstrap needs the single
  `via_seed_dial` discoverer with `min_peers: 0`; the checked-in
  `deploy/station/config.json` has it.
- **The station is crash-looping with a cookie error.** The `station-cookie` init container creates
  `/home/app/.erlang.cookie` in the `station_home` volume. Re-run
  `docker compose -f deploy/compose.yml up -d station`; the init container rewrites it.
- **The gateway stays degraded with `{unresolved, procedure_not_advertised}`.** The lab realm
  fixture advertises its boot-claim procedure with a TTL and does not re-advertise. This can happen
  after a long-running lab and a gateway restart. Restart the fixture, give it a moment, then
  restart the gateway:

  ```bash
  docker compose -f deploy/compose.yml restart ot-realm-fixture
  sleep 3
  docker compose -f deploy/compose.yml up -d --force-recreate --no-deps ot-gateway
  ```
- **Port 4000 is already in use.** Stop the local Phoenix dev server or change the published port
  in `deploy/compose.yml`.
- **The scan cannot resolve `legacy-edge`.** The attacker container is not on `internet_net`. Check
  the Compose file and recreate the stack.

## As-is only

If you only want the attack demo, without the mesh services:

```bash
./scripts/demo.sh
```

It starts the controller, legacy edge, attacker, and dashboard, runs the scan, and prints the same
URLs. The Mesh button stays disabled because the station and gateway are not running.
