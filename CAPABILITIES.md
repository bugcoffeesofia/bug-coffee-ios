# Bug Coffee — App Capabilities Specification

> **Superseded by [`docs/`](docs/README.md).** This file is the original Android-only
> overview; the maintained, platform-neutral specification (and everything added since —
> the live stamp-count sync, the watch app's extra screens, bean deep links, the pass's
> location relevance, build instructions and acceptance tests) lives in `docs/`. Kept here
> for its Android mapping notes.

> **Purpose:** A complete, platform-neutral description of what the Bug Coffee iOS
> app does, so the same product can be rebuilt on Android. This documents
> *behavior, data, and integrations* — not Swift/SwiftUI implementation details.
> Where an iOS mechanism has a direct Android equivalent, it is noted.

---

## 1. Product overview

Bug Coffee is a **loyalty-card + coffee companion** app for a specialty coffee shop
(bugcoffee.com, Bulgaria). The core loop is: **log in → show a loyalty QR to the
barista**. Around that core, the app adds a browsable menu, a manual stamp
tracker, an Apple Health caffeine log, a "find my blend" quiz, a group-order
iMessage extension, a home-screen widget, and a companion watch app.

The backend is **Google Firebase** (the shop's existing web app). This app does
**not** run its own server. It authenticates against Firebase and otherwise keeps
all state **on-device** (local storage + platform share groups).

### 1.1 Key architectural facts (important for Android)

- **The loyalty identity is the Firebase Auth UID.** The QR code the barista
  scans is literally the account's UID string (QR error-correction level **H**).
  Nothing else is encoded. Everything visual (card, Wallet pass, watch QR) is
  derived from that one string.
- **Login is a single REST call** to Google Identity Toolkit — no Firebase SDK is
  strictly required (though on Android using the Firebase Auth SDK is the natural
  choice). Auth is **not** App Check-gated, so email/password sign-in works from a
  native client with only the public web API key.
- **The live stamp count is App Check-gated on the backend and is intentionally
  NOT read.** Stamps are tracked **manually** by the user (tap +/−). This is a
  deliberate scope decision, not a missing feature — replicate it on Android.
- **No menu API exists.** The drinks/beans menu, prices, and tasting notes are
  **hard-coded** in the app from the shop board and webshop. Android should carry
  the same static dataset (see §9).
- The app is **login-gated**: unauthenticated users see only the login screen.

### 1.2 Brand

| Token | Value | Usage |
|-------|-------|-------|
| Brand dark brown | `#1F0409` (rgb 31, 4, 9) | Backgrounds |
| Accent red | `#CC1E41` (rgb 204, 30, 65) | Buttons, highlights, stamps |
| Cream | `#F6EEE3` (rgb 246, 238, 227) | Empty stamp slots |
| Foreground | `#FFFFFF` | Text on dark |

The iOS app is **light-mode only** (`preferredColorScheme(.light)`). Font style is
rounded/bold for the wordmark. Prices display **dual currency**: `€ / лв.`
(Bulgarian lev), lev derived at fixed rate **1 € = 1.95583 лв.**

---

## 2. Component map

The iOS product ships as one app plus four extensions/companions. On Android these
map to a main app, an app widget, a Wear OS app, and a share/deep-link flow (there
is no Android equivalent of an iMessage extension — see §7).

| iOS component | Type | Purpose | Android equivalent |
|---------------|------|---------|--------------------|
| **BugWallet** | Main app | Login, loyalty card, products, stamps, health log | Main app |
| **BugWalletStampWidget** | Home-screen widget | Stamp card at a glance | App Widget (Glance/RemoteViews) |
| **BugWalletWatch** | watchOS app | Loyalty QR on the wrist | Wear OS app |
| **BugWalletMessages** | iMessage extension | Group coffee order in a chat | Share-based flow / deep link (§7) |
| **Apple Wallet pass** | `.pkpass` | Loyalty card in Apple Wallet | Google Wallet loyalty object (§6) |

Data is shared between the main app and its extensions through an **App Group**
(shared key-value store, suite `group.com.zerogravityroom.bugwallet`). On Android,
back this with a shared store your widget/wear code can read (e.g. DataStore in a
shared module, or a ContentProvider for cross-process widget access).

---

## 3. Authentication (§ core)

### 3.1 Sign-in

- **Screen:** email + password form on the brand-dark background. "Sign In"
  button is disabled until both fields are non-empty; shows a spinner while
  loading; email field trims whitespace, disables autocorrect/autocapitalize,
  uses email keyboard.
- **Mechanism:** POST to Google Identity Toolkit
  `signInWithPassword`:

  ```
  POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=<API_KEY>
  Content-Type: application/json
  { "email": <email>, "password": <password>, "returnSecureToken": true }
  ```

  **Public web API key** (safe to embed, same as the shop's web app):
  `AIzaSyDjY4FROGGt9h4Q-V_3InC8Nv2sEeA-FxI`

- **Response fields used:** `localId` (→ the UID, **required**), `email`,
  `idToken`, `refreshToken`. Only `uid` and `email` are actually used downstream;
  tokens are captured but never used (no authenticated backend calls are made).
- **On Android:** simplest is the **Firebase Auth SDK** (`signInWithEmailAndPassword`)
  pointed at the same Firebase project, which returns the same UID. The raw REST
  call also works if you prefer zero SDK dependency.

### 3.2 Error handling

Map Identity Toolkit error codes to friendly text (the API sometimes appends
detail after a space — take the first token):

| Code | Message |
|------|---------|
| `EMAIL_NOT_FOUND`, `INVALID_PASSWORD`, `INVALID_LOGIN_CREDENTIALS` | "Wrong email or password." |
| `USER_DISABLED` | "This account has been disabled." |
| `TOO_MANY_ATTEMPTS_TRY_LATER` | "Too many attempts. Please try again later." |
| (other) | show the raw code |

Also handle: network failure ("network error"), and unexpected/malformed response
("Unexpected response from the server.").

### 3.3 Session persistence

- On successful login, persist **UID** and **email** to local storage.
- On next launch, if a stored UID exists, **restore the session directly** and go
  straight to the card — **no re-login and no token refresh** (the card only needs
  UID + email). This means the app works offline after first login.
- **Sign out** clears the stored UID + email and returns to the login screen.
- There is **no account creation, password reset, or social login** in the app —
  users must already have a Bug Coffee web account.

---

## 4. Main app navigation

After login, a **2-tab** interface:

1. **Card** tab (icon: QR) — the loyalty card (§5).
2. **Products** tab (icon: cup) — the menu (§8).

Login screen replaces everything when signed out.

---

## 5. Loyalty Card tab

Top-to-bottom layout on brand-dark background:

1. **Header:** "Bug Coffee" title, the account email beneath it, and a "Sign out"
   button (accent red) top-right.
2. **Loyalty QR:** the account UID rendered as a QR (level **H**), black on a
   white rounded card, ~180×180 pt, no smoothing/interpolation. Caption: "Show
   this to the barista".
3. **Stamp tracker (manual):**
   - Label "Stamps" and a counter `N / 9` (max 9 stamps = free drink).
   - **−** and **+** stepper buttons (accent). Clamped to 0…9.
   - A **3×3 grid** of stamp slots rendered below (see §5.1).
   - Every change is written to the shared store **and refreshes the widget**.
4. **"Log a coffee" menu** → writes caffeine to Apple Health (§10). A dropdown
   lists six drink types with mg; picking one logs it and shows a confirmation
   ("Espresso logged to Health ☕️") or an error.
5. **UID text** at the bottom: `UID: <uid>` in a monospaced caption, **selectable**
   (copyable) — used for support/debugging.

**Debug-LocalPass build only** (see §6.3): an "Add to Apple Wallet" button and a
"scan a QR & share a pass" button appear above the UID.

### 5.1 Stamp card visual

- 3×3 grid of circular slots. Empty slots: dashed cream-colored circle outline.
- Filled slots (index < count): accent-red ring + a `cup.and.saucer` cup glyph.
- Each stamp is given a **deterministic jitter** — a small rotation (±20°) and
  offset (±12% of slot size), seeded by the slot index via a splitmix64 hash — so
  it looks like hand-stamped ink but renders identically every time (important so
  the widget doesn't visually "jump" between refreshes).
- Reused at three sizes: card (34pt slots), widget small (30pt), widget medium (34pt).

### 5.2 Stamp storage

- Stored as a single integer `bug-coffee.stamps` in the **shared app-group store**,
  clamped 0…9, so the widget can read it.
- `maxStamps = 9`.

---

## 6. Apple Wallet pass → Google Wallet (Android)

On iOS the app can build a **`storeCard` .pkpass** for the logged-in account and
add it to Apple Wallet. On Android the equivalent is a **Google Wallet loyalty
pass (JWT "Save to Google Wallet" flow)**. Re-implement the *capability* (a
scannable loyalty card in the platform wallet), not the .pkpass mechanics.

### 6.1 Pass content (what to reproduce in a Google Wallet loyalty object)

| Field | Value |
|-------|-------|
| Pass type | Store card / loyalty card |
| Serial / object id | account UID (stable → re-issue updates same pass) |
| Organization | "Bug Coffee" |
| Description | "Bug Coffee Loyalty Card" |
| Header field | label "BUG COFFEE", value "Loyalty" |
| Primary field | label "ПЕЧАТИ" (Bulgarian "stamps"), value "0 / 9" *(static in the pass; live count isn't wired)* |
| Secondary field | label "ЧЛЕН" ("member"), value = account email |
| **Barcode** | **QR**, message = account UID, encoding iso-8859-1 |
| **Location** | 42.69323° N, 23.34402° E — shop geofence, 15 m radius (`maxDistance`); surfaces the pass on the Lock Screen nearby, relevant text "Bug Coffee е наблизо" (Google Wallet: `locations` on the loyalty object) |
| Background color | `#1F0409` |
| Foreground color | `#FFFFFF` |
| Label color | `#CC1E41` |
| Images | icon + logo (brand artwork; placeholder art bundled in `PassTemplate/`) |

### 6.2 iOS signing model (context; not needed on Android)

A `.pkpass` must be cryptographically signed with an Apple Pass Type ID
certificate + Apple WWDR cert (detached CMS/PKCS#7 over a SHA-1 manifest, zipped).
Because on-device signing embeds a private key, iOS gates it behind a build flag.
**Google Wallet's model is different** (you sign a JWT server-side or with a
service account), so this whole subsystem is replaced, not ported. If you don't
want Google Wallet at all, the in-app QR (§5) already fully covers "show a card to
the barista" — Wallet is a convenience, not the core.

### 6.3 `LOCAL_PASS_CREATION` feature flag

On iOS, all pass-signing + the QR-scan-and-share flow are compiled only into a
special `Debug-LocalPass` build. In shipping Debug/Release builds these buttons
**do not exist**. The extra flow (Debug-LocalPass only): scan **another** person's
loyalty QR with the camera → build a pass for that UID → share it via the share
sheet. This is a power-user/testing tool, not a mainstream feature — treat as
optional for Android.

---

## 7. Group coffee order (iMessage extension) → Android approach

**iOS behavior:** an iMessage app lets one person start a "coffee run" in a chat,
pick drinks, and send a bubble; everyone else taps the same bubble, adds their
drinks, and sends it back. **The entire order state lives inside the message URL**
(no server). The bubble updates in place instead of spamming the chat.

### 7.1 Order model (reproduce this data model regardless of transport)

- **OrderLine:** `{ participant (UUID), drinkID, decaf (bool), milk (id or none),
  blend (bean id or none/house), qty (1…9) }`.
- **Pricing per line:** base drink price + milk surcharge (**+0.60 €** for
  alternative milk) + decaf surcharge (**free / 0**), × qty.
- **GroupOrder:** a list of lines. Computes total drinks, total price, participant
  list (in first-appearance order), and a merged/aggregated view
  ("2× Cappuccino · oat milk").

### 7.2 Encoding (the "no server" trick)

The order is serialized into URL query items — one `o=` per line:

```
https://bugcoffee.example/group-order?v=3
  &o=<participantUUID>~<drinkID>~<decaf 0/1>~<milkID or ->~<qty>~<blendID or ->
  &o=...
```

- `v=3` is the schema version. **v2 bubbles had 5 fields** (no blend); decoders
  must accept 5- or 6-field lines and default missing blend to "house". This
  backward-compat rule matters if Android needs to read links produced by older
  clients.
- Participants are **opaque per-device UUIDs** — real contact names are never
  available to the extension, so people are shown as **"You" / "Friend 1" /
  "Friend 2"…**

### 7.3 UI behavior

- **Compact view** (drawer): a call to action — "Start a coffee run" or, if joining
  an existing order, "There's a coffee run going — add your drinks!".
- **Expanded view:** "Order so far" (others' drinks + running total), "Your drinks"
  (editable rows with qty stepper, decaf chip, milk picker, bean picker), then the
  full menu with an add (+) button and favorite (★) toggle per item.
- **Submit:** builds a combined order (everyone else's lines untouched + your
  current selection replacing your old lines) and inserts the bubble; the user
  hits send themselves. Button text: "Send order to the chat" / "Add my drinks to
  the order".
- The bubble shows a **rendered image card** (dark card, accent title, up to 5
  aggregated lines + "…more", one-line summary, dual-currency total).

### 7.4 Android recommendation

Android has no in-conversation message extension. Recreate this as a **shareable
deep link**: build the same `?v=3&o=…` URL, share it via the Android share sheet
(or a chat app), and register a deep link / App Link so tapping it opens the app to
the order editor. The order model, encoding, pricing, and "You/Friend N"
labeling all port directly. (Note: without a stable per-device participant id like
iMessage's, you'll need to generate and persist one per install.)

---

## 8. Products / Menu tab

- Two sections: **Drinks** and **Coffee beans** (full data in §9).
- Each row: emoji + name, and a subtitle `size · €X.XX / X.XX лв.`, plus a
  **favorite star** toggle.
- **Favorites float to the top** of their section (in menu order), and are stored
  in the shared app-group store so the **same stars appear in the iMessage
  menu** and vice-versa.
- **Bean rows** are tappable → **Bean detail page**:
  - Shop tasting notes (e.g. "peach · chocolate · berry") + a one-line blurb.
  - Size + dual price.
  - **Personal diary:** a list of **cups**, newest first — every time you drink
    the bean you add an entry, so one bean accumulates a history rather than a
    single verdict. Each cup carries:
    - a 1–5 **star rating** (tap the current star to clear),
    - the **brew method** — espresso-bar drinks (espresso, cortado, latte…) or
      brewed ones (V60, AeroPress, moka pot, cuban, Turkish, cold brew…),
    - the **place** (Bug Coffee, another café, home, work, elsewhere),
    - the **grind size** as free text ("18 clicks", "medium-fine") — grinders
      aren't comparable across machines, so the user's own words are kept,
    - the **date** and a free-form **comment**.
    Swipe to delete a cup, tap one to edit it. The page shows the **average
    score** of the rated cups as a number to one decimal ("3.8") next to the
    rounded stars and the cup count ("5 cups · 4 rated" when some were logged
    without stars). The same average appears on the **bean rows** in the
    products list ("250 г · 12.00 € · ★ 3.8") so beans can be compared without
    opening them. Its rounded form is the star rating the iMessage picker shows
    and the blend-finder quiz scores on.
    Stored per-bean in the shared store as JSON. The pre-diary flat
    `{rating, note}` shape decodes into a first diary entry, so nothing an
    existing user wrote is lost.
- Toolbar **"Find my blend"** button opens the quiz (§8.1).

### 8.1 "Find my blend" quiz

A guided 3-question quiz that recommends beans:

1. **Serving:** Black / With milk.
2. **Caffeine:** Regular / Decaf.
3. **Direction:** Chocolate & nuts / Fruity & bright / Surprise me.

**Scoring** (per bean, filtered to matching caffeine): +2 if flavor direction
matches (fruity vs chocolatey; "surprise me" adds nothing), +1 if milk preference
matches the bean's "loves milk" flag, **+ the user's own journal rating** (0–5) so
beans they liked rise. Show the **top 3**, best first, each with tasting notes,
blurb, current star rating, and a pick button. The pick action is contextual:
"Add to favorites" (from Products) or "Use this blend" (from a group-order line).

Bean taste profiles used by the quiz (fruity / lovesMilk / decaf flags) are in §9.2.

---

## 9. Static data (port verbatim)

Prices are **euro cents**; display dual €/лв at rate **1.95583**. Menu is
hard-coded (no API). Bean prices are the **250 g** bag.

### 9.1 Drinks

| id | Name | Emoji | Price (€) | Size | Milk opt.? | Decaf opt.? |
|----|------|-------|-----------|------|:---:|:---:|
| esp | Espresso | ☕️ | 1.90 | 25 мл | – | ✓ |
| dsp | Double Espresso | ☕️ | 2.60 | 50 мл | – | ✓ |
| ame | Americano | ☕️ | 2.60 | 200 мл | – | ✓ |
| mac | Macchiato | 🥛 | 2.60 | 50 мл | ✓ | ✓ |
| cor | Cortado | 🥛 | 3.10 | 100 мл | ✓ | ✓ |
| flw | Flat White | ☕️ | 3.30 | 150 мл | ✓ | ✓ |
| cap | Cappuccino | ☕️ | 3.10 | 220 мл | ✓ | ✓ |
| lat | Latte | 🥛 | 3.30 | 290 мл | ✓ | ✓ |
| v60 | V60 | 🫖 | 3.30 | 220 мл | – | ✓ |
| ton | Espresso Tonic | 🍹 | 3.30 | 150 мл | – | ✓ |
| tea | Tea | 🍵 | 1.80 | 260 мл | – | – |
| cha | Chai Latte | 🍵 | 3.10 | 290 мл | ✓ | – |
| mtt | Matcha Tea | 🍵 | 3.10 | 260 мл | – | – |
| mtl | Matcha Latte | 🍵 | 3.30 | 290 мл | ✓ | – |
| cho | Hot Chocolate | 🍫 | 3.10 | 220 мл | ✓ | – |

- **Milk options** (alternative milks, +0.60 € each): Oat (`oat`), Almond (`alm`),
  Coconut (`coc`), Pea (`pea`).
- A drink is **"coffee"** (bean-selectable in group orders) exactly when it is
  decaf-able (`allowsDecaf == true`) — i.e. espresso/filter-based.
- Decaf surcharge is **0**.

### 9.2 Beans (250 g)

| id | Name | Price (€) | Tasting notes | Fruity | Loves milk | Decaf |
|----|------|-----------|---------------|:---:|:---:|:---:|
| bbe | Decaf Bette Buna · Ethiopia | 15.30 | forest fruit · caramel · nuts | – | ✓ | ✓ |
| bmb | Bombe · Ethiopia | 13.90 | peach · chocolate · berry | ✓ | – | – |
| sjp | San Jose · Peru | 13.20 | apricot · caramel · black tea | – | ✓ | – |
| mkw | Mukuru West · Uganda | 14.30 | kiwi · blackberry · toffee | ✓ | – | – |
| sir | Siracusa · Colombia | 15.30 | nectarine · melon · blood orange | ✓ | ✓ | – |
| kal | Kalinka Blend | 11.70 | chocolate · honey · apple | – | ✓ | – |
| ban | Bandit Blend | 11.70 | dark chocolate · nuts | – | ✓ | – |
| kul | Kultura House Blend | 11.70 | dense body · natural sweetness | – | ✓ | – |

Blurbs (bean detail): each bean has a one-line description — e.g. Bombe: "Natural
Sidamo heirloom — stone fruit and berries."; Kalinka: "The approachable intro
blend…"; Kultura: "The house blend — Brazilian base, Central American aromatics."
(Full text in `Shared/BlendFinder.swift`.)

### 9.3 Caffeine values (for Health logging)

| Drink | mg caffeine |
|-------|-------------|
| Espresso | 64 |
| Double Espresso | 128 |
| Cappuccino | 64 |
| Latte | 64 |
| Filter Coffee | 95 |
| Decaf | 3 |

*(This is a separate, simpler list used only by the Health logger — six generic
drinks, not the full menu.)*

---

## 10. Apple Health caffeine logging → Google Fit / Health Connect

**iOS behavior:** "Log a coffee" writes a **dietary caffeine** sample to Apple
Health.

- On first use, request **write** authorization for dietary caffeine (the app
  reads nothing).
- Writes one sample: quantity = the drink's mg caffeine, timestamp = now, with the
  drink name as food-type metadata.
- Errors: "Health data isn't available on this device." / "Health access is off.
  Enable Caffeine in Settings…".

**Android equivalent:** write a caffeine/nutrition record via **Health Connect**
(the modern API; Google Fit is deprecated). Request the caffeine write permission,
write the mg value with a timestamp. Same six drinks and mg values (§9.3).

---

## 11. Home-screen widget

- **Widget:** "Stamp Card" — "Your Bug Coffee stamps at a glance."
- **Families:** small and medium.
  - **Small:** the 3×3 stamp grid + `N / 9` counter.
  - **Medium:** "Bug Coffee" title, counter, and a status line — either
    "**Free drink earned! 🎉**" (at 9) or "**X to a free drink**" — beside the grid.
- Brand-dark background, accent counter.
- Reads the stamp count from the shared store; updates only when the app changes
  the count (the app triggers a widget reload on every stamp change).
- **Android:** an **App Widget** (Jetpack Glance) in small/medium sizes reading the
  same shared count; refresh the widget when the count changes.

---

## 12. Companion watch app → Wear OS

- **watchOS behavior:** shows the loyalty QR on the wrist so you can pay without
  the phone.
- The watch **cannot generate the QR itself** (no CoreImage), so the **phone
  renders the QR to a PNG and pushes it** to the watch along with UID + email, via
  **WatchConnectivity `updateApplicationContext`** (delivers the latest value even
  if the watch is asleep/closed; queued for next activation).
- The watch **persists** the received UID/email/QR PNG locally, so it can show the
  card even without the phone nearby.
- If nothing has been received yet: "Sign in on your iPhone to show your loyalty
  card."
- The phone re-pushes the saved UID on every launch (so a returning user's watch
  stays in sync without a fresh login).
- **Android/Wear OS:** use the **Wearable Data Layer API** (`DataClient`) to sync
  the UID (Wear OS *can* render a QR itself, so you can send just the UID string
  and generate the QR on the watch, simplifying this). Persist on the watch for
  offline display.

---

## 13. Shared storage keys (reference)

All cross-component state lives in the app-group store
`group.com.zerogravityroom.bugwallet` (except UID/email/QR which are also in
standard local storage for session restore and watch persistence):

| Key | Type | Meaning | Shared with |
|-----|------|---------|-------------|
| `bug-coffee.uid` | String | Firebase UID | app, watch |
| `bug-coffee.email` | String | Account email | app, watch |
| `bug-coffee.qr` | PNG bytes | Rendered QR (watch only) | watch |
| `bug-coffee.stamps` | Int (0–9) | Manual stamp count | app, widget |
| `bug-coffee.favorites` | String[] | Favorited product ids | app, iMessage |
| `bug-coffee.blend-journal` | JSON `{id: {entries: [{id, date, rating, method, place, grind, note}]}}` | Per-bean tasting diary; legacy `{rating, note}` still decodes | app, iMessage |

**Android:** put the "shared with widget/wear/share-flow" keys in a store your
extensions can read (DataStore in a shared Gradle module, or a ContentProvider for
the widget process). Keep session keys (uid/email) in normal app prefs.

---

## 14. Permissions summary

| Capability | iOS permission | Android equivalent |
|------------|----------------|--------------------|
| Health caffeine write | `NSHealthUpdateUsageDescription` (+ share usage string) | Health Connect caffeine write permission |
| Camera (scan-and-share pass, Debug-LocalPass only) | `NSCameraUsageDescription` | `CAMERA` (only if you port the scan flow) |
| Network (login) | — (default) | `INTERNET` |

The app requests **no** location, contacts, notifications, or tracking permissions.

---

## 15. Non-goals / deliberate limitations (keep on Android)

- **No live stamp count** — stamps are user-tracked, because the real count is
  App Check-gated. Do not attempt to scrape it.
- **No menu/ordering backend** — the menu is static; group orders are peer-to-peer
  via a link, not placed with the shop.
- **No signup/password reset** — accounts come from the shop's web app.
- **No push notifications, no analytics, no in-app purchases.**
- **Light mode only** (a stylistic choice; Android can honor dark mode if desired).
- The iMessage group order is a **social convenience**, not a real transaction —
  no payment, no submission to the shop.

---

## 16. Minimum viable Android port (suggested priority)

1. **Login** (Firebase Auth email/password) → store UID/email, session restore.
2. **Loyalty card** screen: QR from UID (level H), manual stamp tracker (0–9),
   sign out, copyable UID.
3. **Products** tab: static menu (§9), favorites, bean detail with journal,
   "find my blend" quiz.
4. **Health Connect** caffeine logging.
5. **App Widget** (stamp card).
6. **Wear OS** companion (QR on wrist).
7. **Google Wallet** loyalty pass (optional; QR already covers the core).
8. **Group order** via shareable deep link (replaces the iMessage extension).

Items 1–2 are the product's core; everything else is additive.
