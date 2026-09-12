# 6 — Group-order protocol

A "coffee run": one person picks drinks and shares the order into a chat, everyone else adds
theirs and shares it back. **The entire order state lives inside the link** — there is no
server, no account, no database. Any client that can encode and decode the format below can
join an order started by any other.

Reference: `MessagesExtension/Sources/GroupOrder.swift`, `OrderStore.swift`,
`OrderCardRenderer.swift`.

---

## 1. The order model

**OrderLine** — one participant's drink choice:

| Field | Type | Notes |
|-------|------|-------|
| `participant` | UUID | Opaque per-device id (§3) |
| `drinkID` | string | A menu id from doc 3 §1.1 |
| `decaf` | bool | Only meaningful when the drink `allowsDecaf` |
| `milk` | string | An alternative-milk id, or empty = regular milk |
| `blend` | string | A bean id, or empty = house blend. Only meaningful when the drink `isCoffee` |
| `qty` | int | **1…9** |

A line also carries a local-only identity for list editing; it is **not** transmitted.

**GroupOrder** — just a list of lines. All summaries are derived:

- `totalDrinks` = Σ qty
- `totalCents` = Σ line totals
- `participants` = participant ids **in order of first appearance** (this is what makes
  "Friend 1 / Friend 2" labels stable within one order)
- `oneLineSummary` = `"<n> drink(s) · <m> person/people · <total €>"` with correct singulars
- `aggregated` = lines merged by **title** across participants, keeping first-appearance order →
  `[(title, qty)]`, used for the preview card

---

## 2. Pricing

```
unitCents(line) = menu[drinkID].cents
                + (decaf      ? 0  : 0)        // decaf surcharge is 0, kept explicit
                + (milk != "" ? 60 : 0)        // alternative milk, in euro cents
totalCents(line) = unitCents × qty
```

Formatting rules are in doc 3 §1.5: dual `€ / лв.` for totals the user acts on, euro-only for
compact line totals and surcharge labels.

**Line title** — built in this order, joined with `" · "`:

```
<drink name>[ · decaf][ · <milk name lowercased> milk][ · <bean name>]
```

e.g. `Cappuccino · decaf · oat milk · Kalinka Blend`. An unknown milk or bean id is simply
omitted (forward compatibility), and an unknown drink id falls back to showing the raw id.

---

## 3. Participants

- The id is an **opaque UUID per device/install**. Real names are never available to the iOS
  extension, and the protocol deliberately carries nothing identifying.
- Display: **"You"** for the local participant, **"Friend 1"**, **"Friend 2"**… assigned in
  first-appearance order among the *other* participants, recomputed each time an order is
  loaded.
- On a platform with no conversation-scoped identity, **generate a UUID at first launch and
  persist it** (doc 4 §5). The same id must be reused for every order, or your lines will not
  merge with your earlier ones.

---

## 4. The wire format

```
https://<host>/group-order?v=3
  &o=<participantUUID>~<drinkID>~<decaf 0|1>~<milkID|->~<qty>~<blendID|->
  &o=…
```

- One `o=` query item **per line**, in order.
- Fields are separated by `~`. Empty milk/blend are written as `-`.
- `v=3` is the schema version.
- The reference app uses the placeholder host `bugcoffee.example`. **Pick a host you control**
  if you want tappable links/App Links; the decoder ignores scheme, host and path entirely and
  reads only the query, so changing the host is compatible in both directions.

### 4.1 Decoding rules (be strict about these)

- Accept **5 or 6** `~`-separated fields. **v2 links had 5** (no blend); a missing blend
  defaults to **house blend** (empty). This backward compatibility is required — older clients
  are still out there.
- **Skip** any line whose participant is not a valid UUID, whose qty is not an integer > 0, or
  whose field count is neither 5 nor 6. One bad line must not discard the order.
- Do **not** reject unknown drink/milk/bean ids — keep the line (the menu may have moved on) and
  render what you can.
- Ignore any query item that is not `o=` (including `v`, beyond noting the version).

### 4.2 Preview card

For the chat bubble/link preview: a 300×175 pt (×3 scale) brand-dark image with

- `"☕️ Bug Coffee"` in accent bold 18 at (16, 14),
- `"Group order"` at 70% white, 12, at (16, 38),
- up to **5** aggregated lines as `"<qty>× <title>"`, white medium 13, from y=62, 18pt apart,
- `"+ N more…"` at 60% white 12 when there are more,
- the `oneLineSummary` at 50% white 11, 40pt from the bottom,
- the **dual-currency total** in white bold 12, 24pt from the bottom.

Caption "Bug Coffee group order", subcaption = `oneLineSummary`, and the accessibility/summary
text `"Bug Coffee group order — <oneLineSummary>"`.

---

## 5. Editing and merge semantics

The rule that makes the serverless design work:

> **On submit, replace only your own lines; keep every other participant's lines exactly as
> they arrived.**

- Load: decode the link, split lines into **mine** (participant == me) and **theirs**.
- Show theirs read-only under "Order so far"; mine editable under "Your drinks".
- Because your previous lines are loaded back into the editor, re-opening an order **edits**
  your choice instead of duplicating it.
- Adding a drink that already exists as a **plain** line of yours (no decaf, no alternative
  milk, house blend) **increments its quantity**; any modifier makes it a separate line.
- Submit = `theirs + mine`, re-encoded. The user sends the message themselves — never send on
  their behalf.

Last-writer-wins on a shared field would be a problem; it isn't one here, because nobody ever
writes anybody else's lines. Two people replying simultaneously to the same order will produce
two links, each missing the other's newest drink — the next person to add resolves it by
replying to the newer one. Acceptable for a coffee run; do not build conflict resolution.

---

## 6. Favorites and bean ratings inside the order

- The order UI reads the **same favorites set** as the Products tab from shared storage, so
  starring a drink in either place floats it to the top in both (doc 3 §3).
- The bean picker shows each bean's **rounded journal rating** as stars next to its name, and
  offers **"Find my blend…"** (the same quiz, with the pick label "Use this blend") for the
  undecided.
- Neither favorites nor ratings travel in the link — they are local, per person.
