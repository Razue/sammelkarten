## DEV_PLAN_NIP: Sammelkarten Nostr Integration & Relay Strategy (English)

Status: Draft  
Audience: Developers building the Elixir implementation  
Source Spec: `NIP-Collectible-Cards-Trading.md`  

---
### 0. Goal & Principles
Decentralized, verifiable ownership + trading without a central DB as single source of truth. Nostr events = authoritative log; local DB/cache = accelerated projection. Minimal, well versioned custom kinds; reuse existing NIPs (16, 26, 33, 51, 94, optionally 04/44 for encrypted DMs, 36 for ephemeral, 33 for parameterized replaceable).

---
### 1. Review & Adjustments to Current Spec
Current header range: 32121–32125, file already adds 32126 (Portfolio). Proposal: reserve 32121–32130.
Additional needs:
1. Cancel / Invalidate trade offer (either own event kind 32127 or parameterized replaceable `d=offer:<id>`)
2. Optional offer update (better: new offer + cancel old one → immutability preserved)
3. Price alert subscription possibly parameterized replaceable (per card + direction) instead of simple immutable → easier overwrite
4. Global card collection more granular: (a) Card definition events (32121) param replaceable per card (`d=card:<card_id>`) instead of one huge list; (b) Optional snapshot/event 32122
5. User collection (current 32122) → param replaceable per user snapshot (JSON) vs per-card events (scaling tradeoff) or NIP-51 list
6. Portfolio snapshot (32126) as replaceable (NIP-16) or param replaceable (`d=portfolio:<pubkey>`)
7. Integrity: hashes for images (NIP-94 / tag `x=<sha256>`), signature standard Nostr

Updated mapping (recommended):
| Purpose | Kind | Format | Notes |
|---------|------|--------|-------|
| Card Definition | 32121 | Param Replaceable (`d=card:<id>`) | Metadata + image tag |
| User Collection Snapshot | 32122 | Param Replaceable (`d=collection:<pubkey>`) | Aggregated quantities JSON |
| Trade Offer | 32123 | Immutable | Lifecycle: Offer + optional Cancel (32127) + Execution (32124) |
| Trade Execution | 32124 | Immutable | References Offer + counterparty |
| Price Alert Subscription | 32125 | Param Replaceable (`d=alert:<card_id>:<direction>`) | One alert combo per user |
| Portfolio Snapshot | 32126 | Param Replaceable (`d=portfolio:<pubkey>`) | Aggregated values |
| Trade Offer Cancel | 32127 | Immutable | Tag [`e`,<offer_event_id>,"cancel"] |

---
### 2. Phases & Steps

#### Phase 1: Foundations (Elixir Nostr Client & Domain Model)
1. Library choice / minimal internal modules (`Sammelkarten.Nostr.Event`, `Signer`, `RelayClient`)
2. Event struct + canonical JSON ordering for ID hash
3. Schnorr (secp256k1) signature via existing lib or NIF (prefer existing)
4. Unit tests: sign → verify → roundtrip

#### Phase 2: Spec Refinement & Validators
1. Module `Sammelkarten.Nostr.Schema` with per-kind validation
2. Tag normalization & required/optional rules (e.g. offer: card, type, price OR exchange_card; quantity>=1)
3. Error codes (atoms) for UI
4. Property-based tests (StreamData) for event generation + validation

#### Phase 3: Card Definition Publishing
1. Admin key handling (ENV secret / delegation NIP-26?)
2. Function `publish_card_definition(card_struct)` → 32121 event
3. Upsert logic (param replaceable: same `d` overwrites)
4. Indexer stores latest version (ETS/Mnesia)

#### Phase 4: User Collection Snapshot
1. Aggregate from local state (executions + initial import)
2. Encode entire map (card_id => qty) as JSON in content (compression optional later)
3. Publish & rehydrate path test

#### Phase 5: Trade Offers & Lifecycle
1. Create offer (32123): builder + validator
2. Execution flow: counterparty signs execution (32124) referencing offer id
3. Cancel event (32127) optional: mark offer stale
4. Indexer status: open | executed | cancelled
5. Conflict rules: execution only if open & not expired

#### Phase 6: Portfolio Snapshot
1. Compute values / P&L locally → publish (32126)
2. UI LiveView subscribes & updates

#### Phase 7: Price Alerts
1. Param replaceable alerts per (card,direction) → 32125
2. Local watcher GenServer: subscribes trades + price feed → triggers notification (UI event / DM later NIP-04)

#### Phase 8: Media (Images) Integration
1. Upload pipeline: compute sha256, obtain URL
2. Optional NIP-94 event (or direct tag in card event minimal first)
3. Verify hash on load

#### Phase 9: Indexer & Projection Layer
1. GenServer `Sammelkarten.Nostr.Indexer` with subscriptions filters:
   - Card defs (k=32121)
   - Offers / Executions / Cancels (32123/24/27)
   - Collections (32122)
   - Portfolio (32126)
2. ETS tables: cards, offers, executions, collections, portfolio
3. Rebuild procedure: clear tables → replay since=0
4. Catch-up: incremental since <latest_timestamp>

#### Phase 10: Own Relay (Minimal)
1. Goal: guaranteed persistence + specialized filtering + moderation
2. Architecture: Bandit/WebSock → JSON RPC: `EVENT`, `REQ`, `CLOSE`, `COUNT` (NIP-01)
3. Persistence: Mnesia / DETS / SQLite (pragmatic: SQLite; append only initially)
4. Indexes: by kind, pubkey, tags (card, d, e) – precompute composite keys
5. Rate limiting / spam: simple bucket per pubkey
6. Retention: keep only latest param replaceable per (kind,d); full history for immutable kinds
7. Relay config: allow list (32121–32130 + standard kinds)

#### Phase 11: LiveView Integration
1. PubSub bridge: indexer broadcasts domain events (e.g. :offer_created)
2. UI components: Offer list, Offer detail (dynamic status), Portfolio panel
3. Optimistic UI for new offer (pending relay ACK → finalize / rollback)

#### Phase 12: Migration of Existing Data
1. Export cards → 32121 events deterministic order
2. Export user collections → 32122 snapshots
3. Trades → historical offers + executions (preserve timestamps or embed original ts JSON if override blocked)
4. Verification: replay → reconstructed inventory == original

#### Phase 13: Tests & Quality
1. Unit: event builder, validator, signer
2. Integration: publish → relay → indexer ingest
3. Property: offer lifecycle invariants (no double execution)
4. Load: 10k offers / 50k executions replay timing
5. Chaos: network loss, relay timeout, duplicate events

#### Phase 14: Security & Key Handling
1. Abstract keystore (hot vs cold); admin delegation via NIP-26
2. Anti front-running: optional commitment pattern (hash → reveal) for rare/high value trades (later)
3. Signing service isolation (separate process / port)

#### Phase 15: Deployment & Monitoring
1. Relay deploy (Fly.io / container) + health checks (/metrics)
2. Metrics: ingest_count, latency_ms, open_offers
3. Alerting: failed signatures, replay divergences

#### Phase 16: Extensions (Backlog)
- NIP-04 / NIP-44 encrypted negotiation
- Delegated offers (NIP-26) via market bot
- Ephemeral streaming price ticker (NIP-36) instead snapshots
- Merkle proof batch export (off-chain audit)
- Zero-knowledge privacy (longer term)

---
### 3. Module / Component Interfaces (Elixir)
```
Sammelkarten.Nostr.Event
  build(kind, tags, content, opts) :: {:ok, %Event{}} | {:error, reason}
Sammelkarten.Nostr.Signer
  sign(event, privkey) :: {:ok, event_with_id_sig}
Sammelkarten.Nostr.RelayClient
  publish(event) :: {:ok, :accepted | :pending} | {:error, reason}
  subscribe(filters, handler_pid)
Sammelkarten.Nostr.Indexer
  state() -> %{cards: map(), offers: map(), ...}
  fetch_offer(id)
Sammelkarten.Trading
  create_offer(attrs) -> {:ok, offer_event}
  cancel_offer(id) -> {:ok, cancel_event}
  execute_offer(id, counterparty, qty) -> {:ok, exec_event}
Sammelkarten.Portfolio
  snapshot(pubkey) -> {:ok, event}
Sammelkarten.Alerts
  upsert_alert(pubkey, card_id, direction, threshold)
```

---
### 4. Tags & Validation Rules (Short)
Offer (32123):
- Required tags: card, type (buy|sell|exchange), quantity (>0), (price OR exchange_card), expires_at optional
- Reject if quantity > max_supply (reference card def)
Execution (32124):
- Required: offer_id, buyer, seller, card, quantity, price
- Validate quantity <= remaining (offer.quantity - executed)
Cancel (32127):
- Required: e (offer id), reason optional (content JSON)
Snapshot (32126):
- Numeric tags: total_value, profit_loss, card_count

---
### 5. Errors & Retry Strategy
Publish fail: retry with backoff (0.5s,1s,2s,5s) up to N max → then UI warning.  
Missing ACK: mark event pending; if none within T seconds → retry other relay.  
Index divergence: periodic hash (sorted event ids) vs local; mismatch → full resync.

---
### 6. Example: Offer Builder (Pseudo)
```elixir
attrs = %{card_id: "alpha-001", type: :sell, price: 1000, quantity: 2, expires_at: 1_736_000_000}
with {:ok, ev} <- EventBuilders.offer(attrs, user_keys),
     {:ok, _} <- RelayClient.publish(ev) do
  :ok
end
```

---
### 7. Rollout Plan (Iterations)
Sprint 1: Foundations + Card Definition + Indexer Basic  
Sprint 2: Offers + Executions + UI Listing  
Sprint 3: Collection & Portfolio Snapshots + Cancel  
Sprint 4: Alerts + Media Hash Validation  
Sprint 5: Own Relay (MVP) + Migration Script  
Sprint 6: Hardening, Load, Monitoring, Docs

---
### 8. Success Metrics
- <500ms offer roundtrip (publish → display)  
- Full state rebuild <10s @ 50k events  
- 0 unexplained divergences after 24h  
- Core module test coverage >85%

---
### 9. Open Decisions (ADR Candidates)
1. Card definition granular vs global snapshot – propose granular (32121) + optional rollup
2. Collection storage format: JSON vs many tags (prefer JSON for compactness)
3. Relay DB backend: SQLite (pragmatic) vs Mnesia (light) vs Postgres (scaling). Start: SQLite.
4. Image hash: sha256 vs blake3 (sha256 for NIP-94 compatibility)

---
### 10. Immediate Next Steps
1. Update NIP document (kind range + new kinds + param replaceable notes)
2. Implement `Sammelkarten.Nostr.Event` + signature tests
3. Implement card definition publisher (32121) + indexer subscription
4. Small admin UI form for card creation → publish/ACK feedback

---
End.
