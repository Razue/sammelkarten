# NIP-Collectible-Cards-Trading

## Title: Collectible Cards Trading Events for Nostr
## Author: Razue
## Status: Draft
## Created: 2025-08-15
## Kind Range: 32121–32125

---

### Purpose
Defines custom Nostr event kinds for decentralized collectible card trading, portfolio management, and market features.

---

## Event Kinds

### Kind 32121: User Card Collection
Represents a user's current card collection.
- `pubkey`: User's public key
- `created_at`: Timestamp
- `tags`:
  - `['card', <card_id>, <quantity>]` for each card
- `content`: Optional notes or metadata

### Kind 32122: Card Trade Offer (Buy/Sell)
Represents a buy or sell offer for a card.
- `pubkey`: Offer creator's public key
- `created_at`: Timestamp
- `tags`:
  - `['card', <card_id>]`
  - `['type', 'buy' | 'sell']`
  - `['price', <price>]`
  - `['quantity', <quantity>]`
  - `['expires_at', <timestamp>]`
- `content`: Optional offer description

### Kind 32123: Trade Execution Confirmation
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

### Kind 32124: Card Price Alert Subscription
Represents a user's subscription to price alerts for a card.
- `pubkey`: Subscriber's public key
- `created_at`: Timestamp
- `tags`:
  - `['card', <card_id>]`
  - `['threshold', <price>]`
  - `['direction', 'above' | 'below']`
- `content`: Optional alert notes

### Kind 32125: User Portfolio Snapshot
Represents a snapshot of a user's card portfolio value and performance.
- `pubkey`: User's public key
- `created_at`: Timestamp
- `tags`:
  - `['total_value', <value>]`
  - `['profit_loss', <amount>]`
  - `['card_count', <count>]`
- `content`: Optional summary or analytics

---

## Example

```json
{
  "id": "<event_id>",
  "pubkey": "<user_pubkey>",
  "created_at": 1692105600,
  "kind": 32122,
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

---

## Compatibility
- Follows Nostr event structure
- Works with existing Nostr relays and clients
