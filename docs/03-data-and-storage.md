# 3 — Data and storage

Everything the app knows that is not the signed-in identity. The datasets are **static** — the
shop has no menu API — so port them verbatim.

Reference: `Shared/CoffeeMenu.swift`, `Shared/BlendData.swift`, `Shared/SharedKeys.swift`,
`Shared/StampCard.swift`, `Shared/BeanLink.swift`.

---

## 1. The menu

Two categories: **drinks** (transcribed from the board in the shop) and **beans** (whole-bean
bags from the webshop). One record shape for both:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Short stable code. **Travels in the group-order link and in deep links — never change one.** |
| `name` | string | |
| `emoji` | string | Shown before the name |
| `cents` | int | Base price in **euro cents**. For beans, the 250 g bag. |
| `size` | string | Displayed under the name, in Bulgarian units ("220 мл", "250 г") |
| `category` | drink \| beans | |
| `allowsMilk` | bool | Can be made with alternative milk |
| `allowsDecaf` | bool | Can be made decaf |

Derived: **`isCoffee` = (category == drink) && allowsDecaf** — espresso- or filter-based, so the
drinker may choose the bean. The two flags coincide by design; keep the derivation rather than a
third flag.

### 1.1 Drinks (menu order)

| id | Name | Emoji | € | Size | Milk | Decaf |
|----|------|-------|------|------|:----:|:-----:|
| `esp` | Espresso | ☕️ | 1.90 | 25 мл | – | ✓ |
| `dsp` | Double Espresso | ☕️ | 2.60 | 50 мл | – | ✓ |
| `ame` | Americano | ☕️ | 2.60 | 200 мл | – | ✓ |
| `mac` | Macchiato | 🥛 | 2.60 | 50 мл | ✓ | ✓ |
| `cor` | Cortado | 🥛 | 3.10 | 100 мл | ✓ | ✓ |
| `flw` | Flat White | ☕️ | 3.30 | 150 мл | ✓ | ✓ |
| `cap` | Cappuccino | ☕️ | 3.10 | 220 мл | ✓ | ✓ |
| `lat` | Latte | 🥛 | 3.30 | 290 мл | ✓ | ✓ |
| `v60` | V60 | 🫖 | 3.30 | 220 мл | – | ✓ |
| `ton` | Espresso Tonic | 🍹 | 3.30 | 150 мл | – | ✓ |
| `tea` | Tea | 🍵 | 1.80 | 260 мл | – | – |
| `cha` | Chai Latte | 🍵 | 3.10 | 290 мл | ✓ | – |
| `mtt` | Matcha Tea | 🍵 | 3.10 | 260 мл | – | – |
| `mtl` | Matcha Latte | 🍵 | 3.30 | 290 мл | ✓ | – |
| `cho` | Hot Chocolate | 🍫 | 3.10 | 220 мл | ✓ | – |

### 1.2 Beans (250 г, menu order)

| id | Name | € | Tasting notes | Fruity | Loves milk | Decaf |
|----|------|------|---------------|:------:|:----------:|:-----:|
| `bbe` | Decaf Bette Buna · Ethiopia | 15.30 | forest fruit · caramel · nuts | – | ✓ | ✓ |
| `bmb` | Bombe · Ethiopia | 13.90 | peach · chocolate · berry | ✓ | – | – |
| `sjp` | San Jose · Peru | 13.20 | apricot · caramel · black tea | – | ✓ | – |
| `mkw` | Mukuru West · Uganda | 14.30 | kiwi · blackberry · toffee | ✓ | – | – |
| `sir` | Siracusa · Colombia | 15.30 | nectarine · melon · blood orange | ✓ | ✓ | – |
| `kal` | Kalinka Blend | 11.70 | chocolate · honey · apple | – | ✓ | – |
| `ban` | Bandit Blend | 11.70 | dark chocolate · nuts | – | ✓ | – |
| `kul` | Kultura House Blend | 11.70 | dense body · natural sweetness | – | ✓ | – |

All beans use the emoji 🫘, `allowsMilk = false`, `allowsDecaf = false` (the `bbe` bag *is* the
decaf one — that is the `decaf` taste flag in §2, not the drink modifier).

### 1.3 Alternative milks

`oat` Oat · `alm` Almond · `coc` Coconut · `pea` Pea. **Surcharge +0.60 € (60 cents) each.**
"Regular milk" is the absence of a milk id (empty string), and costs nothing extra.

### 1.4 Decaf

**Surcharge 0.** Kept as an explicit constant so the pricing rule stays visible if it changes.

### 1.5 Prices

- Stored as **integer euro cents**. Never use floating point for money.
- Displayed in **dual currency**: `12.00 € / 23.47 лв.`, lev derived at the fixed rate
  **1 € = 1.95583 лв.** (Bulgaria's official conversion rate), formatted to 2 decimals.
- Euro-only form (`12.00 €`) is used for compact spots: line totals, surcharge menu titles.

---

## 2. Bean taste profiles ("find my blend")

Per bean, keyed by bean id:

| Field | Type | Meaning |
|-------|------|---------|
| `tastingNotes` | string | The shop's published notes (table §1.2) |
| `blurb` | string | One-line description (§2.1) |
| `fruity` | bool | Fruit-forward naturals/bright singles, vs chocolate/nuts/caramel |
| `lovesMilk` | bool | Dense/sweet enough to shine in milk drinks |
| `decaf` | bool | It is the decaf bag |

### 2.1 Blurbs (verbatim)

| id | Blurb |
|----|-------|
| `bbe` | Sugarcane-process Ethiopian decaf that keeps the bean's character. |
| `bmb` | Natural Sidamo heirloom — stone fruit and berries. |
| `sjp` | Smooth washed Peruvian, sweet and clean. |
| `mkw` | Natural from the Rwenzori mountains, wild and bright. |
| `sir` | Balanced natural Colombian — neither too acidic nor too bitter. |
| `kal` | The approachable intro blend, balanced for espresso and filter. |
| `ban` | Darker espresso blend, full-bodied and forgiving. |
| `kul` | The house blend — Brazilian base, Central American aromatics. |

### 2.2 Sorting rule for favorites

`favoritesFirst(items, favorites)` = the favorited items **in menu order**, followed by the rest
**in menu order**. Applied per section, in both the Products list and the group-order menu.

### 2.3 Quiz scoring (must match everywhere)

```
candidates = beans where info.decaf == wantsDecaf
score(bean) = (flavor == chocolatey && !info.fruity ? 2 : 0)
            + (flavor == fruity     &&  info.fruity ? 2 : 0)
            + (wantsMilk == info.lovesMilk ? 1 : 0)
            + journal[bean].roundedRating          // 0…5, user's own average
result = candidates sorted by score descending, first 3
```

`flavor == surprise` contributes nothing — it just removes the flavor filter. Ties keep menu
order (a stable sort). The journal term is what makes the quiz personal, so it must read the
same diary the bean pages write (§4).

---

## 3. Persisted state

Two scopes in the reference app:

- **App-private** — session identity, and the watch's copy of the card.
- **Shared** (an App Group, suite `group.com.bugcoffee.bugcoffee`) — everything a widget,
  watch or share-sheet surface has to read.

| Key | Type | Meaning | Scope | Written by | Read by |
|-----|------|---------|-------|-----------|---------|
| `bug-coffee.uid` | string | Firebase UID | app-private | app, watch | app, watch |
| `bug-coffee.email` | string | Account email | app-private | app, watch | app, watch |
| `bug-coffee.refresh` | string | Firebase refresh token | app-private | app | app (stamp sync only) |
| `bug-coffee.qr` | PNG bytes | Rendered loyalty QR | app-private (watch) | watch | watch |
| `bug-coffee.stamps` | int 0…9 | Stamp count | shared | app, watch | app, widget, watch |
| `bug-coffee.favorites` | string[] | Favorited product ids, **sorted** | shared | app, group-order UI | both |
| `bug-coffee.blend-journal` | JSON (§4.1) | Tasting diary, per bean | shared | app | app, group-order UI, quiz |

Rules:

- The stamp count is **clamped on read and on write** — never trust a stored value.
- Writing the stamp count must **trigger a widget reload** and **push to the watch** in the same
  step; make that a single function so no call site can forget.
- Favorites toggle is "insert, or remove if already present", then store **sorted** for a stable
  file.
- On a platform where the widget runs in a separate process, pick a store that supports that
  (e.g. a shared-module DataStore, or a content provider). Session keys can stay app-private.
- The refresh token is a **credential**. Keep it out of shared storage, and prefer the
  platform's secure store (keychain/keystore) over plain preferences — the reference app uses
  plain preferences, which a port should improve on.

---

## 4. The tasting diary

One diary per bean; one entry per **cup** (the same bean tastes different as a cortado and as a
moka pot, so a bean accumulates a history rather than a single verdict).

**Entry**

| Field | Type | Notes |
|-------|------|-------|
| `id` | uuid | Stable across edits |
| `date` | date | Date only in the UI |
| `rating` | int | **0 = unrated**, else 1…5 |
| `method` | enum | §4.2 |
| `place` | enum | §4.3 |
| `grind` | string | **Free text on purpose** — "18 clicks", "medium-fine", "Niche 15" mean something to their owner and nothing to another grinder |
| `note` | string | Free-form comment |

**Derived per bean**

- `ratedCount` = entries with rating > 0.
- `averageRating` = exact mean of rated entries, 0 when none — displayed to one decimal ("3.8").
- `rating` = the **rounded** average; this is the star count the quiz scores on and the
  group-order bean picker shows.
- `latestNote` = the newest non-empty comment (for one-line summaries).
- Entries are kept and displayed **newest first**.
- An entry is **empty** when `rating == 0 && grind == "" && note == ""`; empty entries are not
  saved (and are deleted if an existing one is emptied).

### 4.1 Storage format

Stored under `bug-coffee.blend-journal` as one JSON object keyed by bean id:

```json
{
  "kul": {
    "entries": [
      { "id": "8B0F…", "date": 779452800.0, "rating": 4, "method": "cortado",
        "place": "bugCoffee", "grind": "18 clicks", "note": "syrupy" }
    ]
  }
}
```

Two encoding details to get right if a port must read files written by the iOS app:

- **`date` is a number: seconds since 2001-01-01T00:00:00Z** (Apple's reference date), not the
  Unix epoch. Convert with `unix = value + 978307200`.
- **`id` is an uppercase UUID string.**

A greenfield port that never shares files with iOS should use ISO-8601 or epoch milliseconds
instead — just pick one and document it. If both platforms must interoperate (e.g. through a
future export/import), standardize on the iOS shape above.

**Legacy shape:** the diary replaced a flat `{ "rating": n, "note": "…" }` per bean. A decoder
must accept that and turn it into a **single first entry** (dropping it only when both are
empty), so nothing a long-standing user wrote is lost. Keep this compatibility in any port that
might read old data.

### 4.2 Brew methods

Ids are the stored values; keep them exactly.

**Espresso bar** (in picker order): `espresso` Espresso ☕️ · `doubleEspresso` Double espresso ☕️
· `americano` Americano ☕️ · `macchiato` Macchiato 🥛 · `cortado` Cortado 🥛 ·
`flatWhite` Flat white 🥛 · `cappuccino` Cappuccino 🥛 · `latte` Latte 🥛 ·
`espressoTonic` Espresso tonic 🍹

**Brewed**: `v60` V60 / pour-over 🫖 · `chemex` Chemex 🫖 · `aeropress` AeroPress ⏳ ·
`frenchPress` French press ⏳ · `mokaPot` Moka pot 🔥 · `cuban` Cuban (cafecito) 🔥 ·
`turkish` Turkish 🔥 · `coldBrew` Cold brew 🍹 · `drip` Filter / drip 🫖 · `other` Other ☕️

Default for a new entry: `espresso`. The espresso/brewed split is a property of the method
(`isEspressoBased`), used only to group the picker.

### 4.3 Brew places

`bugCoffee` Bug Coffee 🐞 · `otherCafe` Another café 🏠 · `home` Home 🏡 · `work` Work 💼 ·
`other` Elsewhere 📍. Default: `bugCoffee`.

Derived: **`grindsOwnBeans` = place is `home` or `work`** — the only places where the drinker
touched the grinder, which drives the grind-field hint (doc 1 §5.2).

---

## 5. Caffeine values (health logging)

A separate, simpler list of six generic drinks — **not** the full menu.

| id | Name | mg caffeine |
|----|------|-------------|
| `espresso` | Espresso | 64 |
| `doubleEspresso` | Double Espresso | 128 |
| `cappuccino` | Cappuccino | 64 |
| `latte` | Latte | 64 |
| `filter` | Filter Coffee | 95 |
| `decaf` | Decaf | 3 |

---

## 6. Identifier inventory

Things other systems (links, stores, wallets) depend on. Changing one is a breaking change.

| Identifier | Value | Used by |
|------------|-------|---------|
| Deep-link scheme + host | `bugcoffee://bean/<beanId>` | Bean pages, share sheet |
| Shared store suite | `group.com.bugcoffee.bugcoffee` | App, widget, watch, group order |
| Widget kind | `BugCoffeeStampCard` | Widget registry |
| Group-order link | `https://bugcoffee.example/group-order?v=3&o=…` | doc 6 (placeholder host — pick a real one you control) |
| Pass type id | `pass.com.bugcoffee.bugcoffee` | doc 5 (Apple-specific) |
| Menu item ids | table §1.1/§1.2 | Group-order link, deep links, favorites, diary keys |
