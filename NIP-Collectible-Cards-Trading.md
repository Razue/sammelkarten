# NIP-Collectible-Cards-Trading

## Title: Collectible Cards Trading Events for Nostr
## Author: Razue
## Status: Draft
## Created: 2025-08-15
## Kind Range: 32121–32127 (proposed reserved block 32121–32130)

---

### Purpose
Defines custom Nostr event kinds for decentralized collectible card trading, portfolio management, and market features.

---

## Event Kinds

Conventions:
- Parameterized Replaceable (NIP-33) Events use a `d` tag (`["d", "<namespace>:<identifier>"]`). Latest wins.
- Immutable Events never change; corrections come as new events (e.g. Cancel, Execution).
- All numeric values encoded as strings (relay compatibility) unless noted.

### Kind 32121: Card Definition (Parameterized Replaceable)
Single Kartendefinition / Metadaten
- `d=card:<card_id>` via tag `["d","card:<card_id>"]`
- Tags: `['name', <name>]`, `['rarity', <rarity>]`, `['set', <set>]`, optional `['image', <url>, 'sha256=<hash>']`
- `content`: optional JSON Zusatzfelder
Updating: Neu publizieren mit gleicher `d` ersetzt alte Version.

### Kind 32122: User Collection Snapshot (Parameterized Replaceable)
- `d=collection:<pubkey>`
- `content`: JSON Objekt `{ "cards": {"card_id": qty, ...} }`
- Optional Aggregat tags: `['total_cards', <int>]`
Granulare Updates: Neuer Snapshot überschreibt alten.

### Kind 32123: Card Trade Offer (Immutable)
Represents a buy or sell offer for a card.
- `pubkey`: Offer creator's public key
- `created_at`: Timestamp
- `tags`:
  - `['card', <card_id>]`
  - `['type', 'buy' | 'sell' | 'exchange']`
  - `['price', <price>]`
  - `['exchange_card', <card_id>]`
  - `['quantity', <quantity>]`
  - `['expires_at', <timestamp>]`
- Optional: `['partial', 'true']` falls Teilfüllungen erlaubt
- `content`: Optional offer description

### Kind 32124: Trade Execution Confirmation (Immutable)
Confirms execution of a trade between two users.
- `pubkey`: Executor's public key
- `created_at`: Timestamp
- `tags`:
  - `['offer_id', <offer_event_id>]`
  - `['buyer', <buyer_pubkey>]`
  - `['seller', <seller_pubkey>]`
  - `['card', <card_id>]`
  - `['quantity', <quantity>]`
  - `['price', <price>]`
- `content`: Optional trade notes

### Kind 32125: Card Price Alert Subscription (Parameterized Replaceable)
- `d=alert:<card_id>:<direction>`
- Tags: `['card', <card_id>]`, `['direction','above'|'below']`, `['threshold', <price>]`
- `content`: optional JSON

### Kind 32126: User Portfolio Snapshot (Parameterized Replaceable)
- `d=portfolio:<pubkey>`
- Tags: `['total_value', <value>]`, `['profit_loss', <amount>]`, `['card_count', <count>]`
- `content`: optional JSON (Breakdown)

### Kind 32127: Trade Offer Cancel (Immutable)
Invalidate / Cancel a previously published offer.
- Tags: `['e', <offer_event_id>, 'cancel']`
- Optional: `['reason', <short_code>]`
- `content`: optional detail / JSON (z.B. {"reason":"expired"})

---

## Example

```json
{
  "id": "<event_id>",
  "pubkey": "<user_pubkey>",
  "created_at": 1692105600,
  "kind": 32123,
  "tags": [
    ["card", "card123"],
    ["type", "sell"],
    ["price", "1000"],
    ["quantity", "2"],
    ["expires_at", "1692192000"]
  ],
  "content": "Selling 2x card123 for 1000 sats each"
}
```

---

## Security & Privacy
- No private keys stored; all events signed by user
- Trading and portfolio events are public unless encrypted
- Users may use pseudonymous pubkeys
- Sensitive Verhandlungen optional via verschlüsselte DMs (NIP-04 / NIP-44)

---

## Compatibility
- Follows Nostr event structure (NIP-01)
- Leverages NIP-16, NIP-33 for ersetzbare Events
- Compatible mit Standard Relays; eigener Relay kann Filter optimieren
