# What this slice proves — and what it does not

Three slices are built: the as-is exposure and takeover, the mesh read path, and the mesh write path
with per-caller authority, replay refusal, and gateway audit.

## Promise vs. what is built

| Claim | What this slice shows | What it does not show |
|---|---|---|
| The controller is reachable from the internet. | A port scan finds 80/tcp and 443/tcp on the shop edge; the REST API answers from the simulated internet. | A real router, firewall, or vendor remote-management module. The `legacy-edge` container is a stand-in for a port forward. |
| The controlling REST endpoints are weakly protected. | Reads are open. Writes use the shared default `admin/admin` account. | A specific vendor's authentication bug, firmware flaw, or cloud portal. |
| A bad actor can take control. | `scripts/attack.sh` changes a target to +50°C and forces defrost with the default credentials. | A real freezer, compressor, or food-safety model. The simulator is a teaching model, not a physics model. |
| The UI login is not a security boundary. | The dashboard's login only gates its own buttons; the controller API is directly reachable and the attacker bypasses the UI. | A production identity provider, SSO, or role model. |
| Stopping the port forward removes the inbound path. | The dashboard loses the legacy path; `scripts/scan-after-retrofit.sh` finds no open edge ports and no controller answer from the simulated internet. | That the legacy controller is safe on its own LAN. It is not; it is just no longer reachable from the internet. |
| The controller is still reachable over the mesh with no inbound port. | The dashboard's Mesh mode resolves `ot/list_freezers` through the local station, dials the gateway, and shows the same freezer data. The gateway accepts no inbound connection from the mesh or OT network; it dials out. | A real multi-station fleet or a public realm. The station is a local island; the realm fixture is a lab stand-in for `macula-realm`. |
| Commands need authority. | The gateway advertises `ot/set_freezer_target`, `ot/start_freezer_defrost`, `ot/stop_freezer_defrost`, and `ot/list_freezer_commands` only to the operator's node id. A second node identity on the same station gets `unauthorized` before the handler runs. Reads stay open. | A realm role or a store-scoped UCAN, multi-operator approval, and dynamic revocation. The operator list is a boot-time environment value. |
| The bridged traffic is sealed end to end. | Every gateway capability is `confidential => required` with `kem_advertise` enabled. The read call report says `sealed: 1`; the gateway accepts a write only when its payload is sealed. | That every deployment in the fleet seals by default, or that the controller link is encrypted. Routing metadata remains visible. |
| A replayed command is refused. | Each write carries a random command id and a wall-clock timestamp. The dashboard's replay probe re-sends the previous id; the gateway refuses it as `command_replayed`. A timestamp outside the two-minute window is `command_expired`. | A durable dedupe store. The guard is in memory, so a replay after a gateway restart is not refused. |
| Every command is audited with a verified caller. | The gateway audit records the wire-verified caller node, the action, the freezer, the command id, and the result. The controller's own audit shows only the gateway's `gateway` account. | Read-path auditing, signed history an auditor can verify without Macula, and audit entries for authorization refusals (those happen before the handler). |
| The gateway does not reuse the controller's default account. | The gateway calls the controller with its own strong `gateway` credential. The attacker and the legacy UI still use `admin/admin`. | That the controller's default account is disabled. It is not, on purpose, until the legacy edge is retired. |

## What the mesh path proves, concretely

Read path:

- The gateway is a real `mcl-om` service: it claims the `ot` org, gets a D25 delegation from the lab
  realm, advertises `ot/list_freezers`, and serves it from the controller's REST API.
- The station is a real Macula station, running locally. The gateway and the laptop both dial out
  to it; neither has an inbound port.
- The dashboard's Mesh mode is a Macula citizen. It resolves the gateway's capability, dials it,
  and normalizes the typed reply. The browser only talks to the local Phoenix app.
- The call is sealed to the gateway's KEM key. The station relays ciphertext.
- The legacy edge can be stopped; the mesh path keeps working.

Write path:

- The dashboard generates the operator's node identity at `/data/operator.key`, connects outbound,
  and writes the node id to `/mesh/operator-node-id`. The gateway entrypoint waits for that file and
  exports it as `OPERATOR_NODE_IDS`.
- The gateway advertises the three write procedures and the command-audit read with
  `{callers, {nodes, [OperatorNodeId]}}`. With no operator id it advertises no write capabilities;
  the read path still serves.
- Each write carries a random command id and a timestamp. The command guard accepts a fresh id once
  and refuses a duplicate as `command_replayed` or a timestamp outside the two-minute window as
  `command_expired`.
- The gateway audit records the wire-verified caller, action, freezer, command id, and result. The
  dashboard renders it; the controller's own audit records only `gateway`.
- The **Try as stranger** probe connects a second identity from `/data/stranger.key`. Its write is
  refused with `unauthorized`, proving the policy is per caller and not a station-wide secret.
- The gateway writes to the controller with its own strong credential, never `admin/admin`.

## What is still missing

1. **Realm authority, not a static allowlist.** The operator id is a boot-time environment value.
   The production shape is a realm role or a UCAN scoped to the store and command, with dynamic
   revocation and multi-operator approval.
2. **Durable command state.** The guard is an in-memory map with a two-minute TTL. A signed,
   durable command log would survive a gateway restart and give an auditor the full trail.
3. **Signed reading history.** Publish each reading as a signed fact and provide an export an
   auditor can verify without Macula.
4. **A real protocol adapter.** The mock is HTTP/REST. Modbus, BACnet, OPC UA, or a vendor API is a
   separate adapter behind the same typed capability shape.
5. **A real deployment story.** `macula-realm` membership, roles, operator approval, and one real
   station crossing. The local fixture is deliberately not that.

## Honest boundaries

- **"No inbound port" is not "nothing can call in."** The gateway still receives commands over its
  outbound connection. What guards them is realm membership and the procedure's policy, not a
  firewall. The dashboard and the demo script say "no port listens."
- **The BEAM release still has loopback control ports.** The release start script requires a node
  name, so EPMD and Erlang distribution listen on `127.0.0.1` and `::1` only. They are not reachable
  from the mesh or OT networks; removing them entirely would mean replacing the release start
  script.
- **The QUIC client still binds a UDP port.** The outbound station link uses an ephemeral local UDP
  socket so responses can arrive. It is a connected client socket, not a general-purpose listener,
  but a UDP scan may show the port as open. There is no TCP service listening on the network.
- **The controller's LAN is still reachable to the gateway.** The controller must sit on a network
  only the gateway can reach. A compromised gateway can still command it.
- **The mock is HTTP/REST.** It does not prove Modbus, BACnet, OPC UA, or a vendor-specific
  protocol. A real adapter is separate work.
- **The demo realm is a fixture.** It pre-publishes the authorization chain and answers the boot
  claim from the verified caller. Its claim advertisement has a TTL and is not periodically
  refreshed, so a gateway restart after a long-running lab may need the fixture restarted first. A
  real deployment uses `macula-realm` membership, roles, and operator approval.
- **The controller's default account still exists in the as-is stack.** The gateway uses its own
  strong credential, but the legacy `admin/admin` account and the legacy edge remain available until
  the retrofit removes them. The lab leaves both in place on purpose, so the before/after contrast
  is visible.
- **The operator allowlist is boot-time state.** The gateway reads `OPERATOR_NODE_IDS` once. If the
  operator identity changes, the gateway must be restarted. There is no dynamic enrollment,
  revocation, or multi-operator approval in this slice.
- **The replay guard is in memory.** It stops a duplicate within two minutes in one gateway process.
  A gateway restart or a longer delay clears the memo; a durable command log is separate work.
- **Authorization refusals are not in the gateway audit.** The stranger is refused before the
  command handler, so only the caller sees `unauthorized`; the gateway audit covers commands that
  reach the handler.
- **Sealing protects the payload, not the routing metadata.** The station still sees the realm,
  procedure, and caller. The controller link is plain HTTP on the OT network.
- **The gateway is a container, not a DIN-rail box.** Hardware, power, and network hardening are
  outside this lab.

## What would make the demo stronger

- A `macula_bridge` raw-tunnel comparison: the bridge can carry the controller's HTTP port, but it
  authorizes per connection and cannot tell `defrost` from `read`. It is a useful contrast, not the
  security boundary.
- A signed reading history export an auditor can verify without Macula.
- A real station crossing and a real realm membership, rather than the local fixture.
- A hardware target for the gateway.

These are deliberately outside the current slices.
