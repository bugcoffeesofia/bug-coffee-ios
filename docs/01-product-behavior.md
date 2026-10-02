# 1 — Product behavior

Every screen, control and state, platform-neutrally. Strings in "quotes" are the exact
user-visible copy; keep them unless you are localizing (see doc 7 §5).

Reference: `BugWallet/Sources/*View.swift`, `BugWalletWatch/Sources`, `StampWidget/Sources`,
`MessagesExtension/Sources`.

---

## 1. App shape

- The app is **login-gated**: with no stored session, the login screen *replaces* the whole UI.
- Signed in, the app is **two tabs**: **Card** (QR icon) and **Products** (cup icon).
- The reference app is **light-mode only** by choice (`preferredColorScheme(.light)`). Other
  platforms may honor dark mode; the card and login screens are dark-on-brand anyway, so only
  the Products list is affected.
- Orientation: portrait on phones; every orientation on tablets. (The reference app pins
  portrait for iPhone in `Info.plist`; large foldable inner displays ignore that, so no layout
  may *depend* on portrait.)
- Every screen must survive a short viewport: the login and card screens **scroll instead of
  clipping** when height runs out (keyboard up, split view, largest accessibility text sizes).
  See `AdaptiveLayout.swift`.

---

## 2. Login screen

Layout, top to bottom, on the brand-dark background:

1. Wordmark "Bug Coffee" (34pt, bold, rounded).
2. Subtitle "Sign in to show your loyalty card".
3. A white rounded card holding two fields:
   - **Email** — email keyboard, autocapitalization **off**, autocorrect **off**, username
     content type; the value is **trimmed of whitespace** before it is sent.
   - **Password** — secure entry, password content type.
4. Error text (when present) — white, centered, footnote size.
5. **"Sign In"** button — accent-red, full width, 50pt tall, corner radius 12.
   - **Disabled** while loading or while either field is empty.
   - Shows a spinner in place of its title while the request is in flight.

Behavior: tapping Sign In clears any previous error, calls the sign-in endpoint (doc 2 §2),
and on success stores the session and shows the Card tab. On failure it shows the mapped error
message (doc 2 §2.3) and stays put.

On a wide display, hold the form to a **readable maximum width (~440pt)** rather than
stretching the fields edge to edge.

---

## 3. Card tab

Top to bottom (single column on a phone):

1. **Header** — "Bug Coffee" (title, bold, white) with the account email beneath it in a
   70%-opacity caption; a **"Sign out"** text button in accent red on the trailing side.
2. **Loyalty QR** — the account UID as a QR, black on a white rounded card (radius 20, 16pt
   inner padding), 180×180pt, **nearest-neighbour scaling (no smoothing/interpolation)**.
   Caption beneath: "Show this to the barista".
3. **Stamp tracker** — see §4.
4. **"Log a coffee"** — see §6.1.
5. **Footer** — `UID: <uid>` in a monospaced caption at 40% opacity, **selectable/copyable**
   (used for support and for signing a pass manually).

On a wide/regular-width display the reference app splits the card in two halves — QR in one,
stamps + buttons in the other — side by side when the space is wider than tall, stacked when
it is taller than wide. The controls half is held to ~440pt wide.

Anything modal (a scanner, alert or share sheet) is anchored at the **root** of the screen, not
inside a section, so it survives a layout change (a foldable opening/closing, a rotation).

### 3.1 Sign out

Clears the stored UID, email and refresh token, stops the stamp sync, and returns to the login
screen. It does **not** clear the stamp count, favorites or the tasting diary — those are
local-only data and survive a sign-out/sign-in cycle.

---

## 4. Stamp tracker (Card tab)

- Row: label "Stamps", then the counter `N / 9` (monospaced digits, accent), then a **−** and a
  **+** button (accent, circle-filled glyphs).
- Below it, the **3×3 stamp grid** (doc 7 §4).
- Below that, a small diagnostics line `Backend: <status>` at 50% opacity (doc 2 §5.4). This is
  developer-facing; a shipping port may hide it or turn it into a quiet "last synced" line.
- The count is **clamped to 0…9**. 9 means a free drink is earned.
- Every change: persist to shared storage → **refresh the widget** → **push to the watch**.
- When a live count arrives from the backend it is **authoritative**: adopt it, even if it
  overrides a manual value the user set. (Reference: `CardView.onReceive(webSync.$backendCount)`.)

---

## 5. Products tab

Two sections in a list: **"Drinks"** then **"Coffee beans"** (data in doc 3 §1).

- **Row**: `<emoji>  <name>` on the first line; on the second, `<size> · <€ price> / <лв price>`
  in a secondary caption. If the bean has rated cups in the diary, ` · ★ 3.8` is appended in
  accent. A **favorite star** button sits on the trailing side (filled + accent when on, grey
  outline at 50% when off), with an accessible label "Add <name> to favorites" /
  "Remove <name> from favorites".
- **Favorites float to the top** of their own section, keeping menu order among themselves.
  Favorites are shared with the group-order menu (doc 3 §3), so a star set in one appears in
  the other; re-read them whenever the tab appears.
- **Drink rows are not tappable.** **Bean rows push the bean page** (§5.1).
- Toolbar: **"Find my blend"** (wand glyph, accent) opens the quiz (§5.3).
- On a wide display this is a two-column split: list on the left, the selected bean's page on
  the right, with the placeholder "Pick a bean to see its tasting notes and your diary." before
  a selection. On a phone it is the usual push navigation.

### 5.1 Bean page

Sections:

1. **Header card** — `<emoji>  <name>` (headline), the shop's **tasting notes** in accent
   (e.g. "peach · chocolate · berry"), the one-line **blurb** in secondary text, then
   `<size> · <dual price>` in a caption.
2. **"Your average"** — only when at least one cup is rated: the average to one decimal
   ("3.8") in accent at title size, the rounded value as ★ characters, and the cup count on the
   trailing side — `"5 cups"`, or `"5 cups · 4 rated"` when some cups carry no stars.
3. **"Diary"** — the cups, **newest first**. Each row shows
   `<method emoji>  <method name>` with the cup's stars on the trailing side, then
   `<place emoji> <place> · <abbreviated date>`, then `Grind: <text>` if set, then the comment
   (up to 3 lines). Tapping a row **edits** that cup; swiping **deletes** it. Last row is
   **"Add a cup"** (plus glyph, accent).
4. Toolbar: a **share** action offering this bean's deep link (§9), and a **favorite star**
   toggle titled "Add to favorites" / "Remove from favorites".

The page reads its diary once when it appears, so navigating between beans must **reset the
view state per bean** (the reference app keys the view by bean id).

### 5.2 Cup editor (add/edit a diary entry)

A modal form titled with the bean name:

- **"How was it?"** — five star buttons. Tapping the star that is already the rating **clears
  it** (back to unrated = 0).
- **"The cup"**:
  - **"Made as"** — the brew method, in two groups: **"Espresso bar"** (espresso, double
    espresso, americano, macchiato, cortado, flat white, cappuccino, latte, espresso tonic) and
    **"Brewed"** (V60/pour-over, Chemex, AeroPress, French press, moka pot, Cuban (cafecito),
    Turkish, cold brew, filter/drip, other). Full list with ids in doc 3 §4.2.
  - **"Where"** — Bug Coffee 🐞 / Another café 🏠 / Home 🏡 / Work 💼 / Elsewhere 📍.
  - **"When"** — a date picker (date only, no time).
- **"Notes"** — **Grind size** as *free text* (placeholder: `Grind size ("18 clicks",
  "medium-fine"…)`) and a multi-line **comment** (placeholder: `What did you think?
  ("syrupy", "sour — grind finer"…)`, 3–6 lines). When the place is *not* one where the drinker
  ground the beans themselves (i.e. not Home or Work), show the footer "Grind is worth noting
  when you ground the beans yourself."
- Toolbar: **Cancel** (✕) and **Save** (✓). **Save is disabled while the entry is empty** —
  empty means rating 0 **and** no grind **and** no comment.
- On save: an entry that is still empty is **deleted** instead of stored; otherwise it is
  inserted or updated by id, and the diary is re-sorted newest-first.

### 5.3 "Find my blend" quiz

A modal form, title "Find my blend", with a **Close** (✕) action:

1. **"How do you drink it?"** — *Serving*: "Black" / "With milk"; *Caffeine*: "Regular" /
   "Decaf" (segmented on phone; plain pickers where segmented controls don't exist, e.g. watch).
2. **"Which direction?"** — "Chocolate & nuts" / "Fruity & bright" / "Surprise me".
3. **"Your matches"** — live-updating as answers change, best first.

Each match row: `<emoji>  <name>` bold, the current rounded star rating in accent (if any) on
the trailing side, tasting notes in accent, the blurb in secondary text, and a capsule
**pick button** whose title is supplied by the caller: **"Add to favorites"** from Products,
**"Use this blend"** from a group-order line. Picking dismisses the quiz.

Scoring (identical everywhere — doc 3 §2.3): filter beans to the chosen caffeine, then
`+2` if the flavor direction matches ("surprise me" adds nothing), `+1` if the milk preference
matches the bean's `lovesMilk` flag, `+` the user's own rounded journal rating (0–5). Show the
**top 3**, highest score first.

---

## 6. Integrations on the Card tab

### 6.1 Caffeine logging ("Log a coffee")

- A full-width accent button, 44pt tall, labelled **"Log a coffee"** with a cup glyph; it reads
  **"Logging…"** and is disabled while a write is in flight.
- Tapping opens a menu of six generic drinks, each `"<name> · <mg> mg"` (doc 3 §5).
- Picking one writes **one dietary-caffeine sample** to the system health store: the drink's
  milligrams, timestamped *now*, with the drink name attached as food-type metadata.
- Result text under the button: `"<Drink> logged to Health ☕️"`, or the error.
- Permission is requested on **first use**, **write-only** — the app reads nothing from the
  health store.
- Errors: `"Health data isn't available on this device."` and `"Health access is off. Enable
  Caffeine in Settings → Health → Data Access."` (adapt the second to the platform's own path).

### 6.2 Wallet pass (feature-flagged on iOS)

Only present in the reference app's `Debug-LocalPass` build (doc 5 §3): an **"Add to
<platform> Wallet"** button that turns into the status label "In Apple Wallet" once the pass is
installed, plus a square accent button that **scans another person's loyalty QR**, asks for a
name ("Name for the pass" / "This name will appear on the shared Wallet pass." / Cancel ·
"Create pass"), builds a pass for that UID and offers it through the share sheet. Errors
surface as footnotes: `"Couldn't build pass: …"`, `"That QR didn't contain a UID."`

Wallet state is re-checked when the app returns to the foreground, since the user may have
removed the pass meanwhile. Treat the scan-and-share flow as **optional** on other platforms.

---

## 7. Home-screen widget

- Name **"Stamp Card"**, description **"Your Bug Coffee stamps at a glance."**
- Two sizes:
  - **Small**: the 3×3 grid (30pt slots) above the `N / 9` counter.
  - **Medium**: a left column with "Bug Coffee" (headline, white), the counter, and at the
    bottom either **"Free drink earned! 🎉"** (at 9) or **"X to a free drink"**; the grid
    (34pt slots) on the right.
- Brand-dark background, accent counter in monospaced digits.
- The count is read from shared storage. It changes **only** when the app writes it, so the
  widget needs no refresh schedule — the app **triggers a reload** on every change. The preview
  placeholder shows 4 stamps.

---

## 8. Watch app

Home is a list of four rows, title "Bug Coffee":

1. **"Loyalty card"** (QR glyph) → the QR the phone rendered, on a white rounded card with
   nearest-neighbour scaling and the caption "Bug Coffee".
2. **"Stamps"** (cup glyph) → the 3×3 grid (34pt), the `N / 9` counter in accent, and either
   **"Free drink ready! 🎉"** or **"X to go for a free drink"**. **Read-only on the watch.**
3. **"Log caffeine"** (drop glyph) → the same six drinks with their mg; tapping one writes the
   sample from the watch (a spinner replaces the mg while writing) and shows the same result
   text. Works standalone.
4. **"Find my blend"** (leaf glyph) → the same quiz and scoring, watch-shaped (plain pickers,
   no pick button — it is a recommendation list here).

Rows 1 and 2 require that the phone has synced an account. Until then both show the prompt
**"Sign in on your iPhone to show your loyalty card"** with a phone glyph. The watch
**persists** the last-received UID, email, QR image and stamp count, so it works with the phone
away or asleep.

Sync direction is **phone → watch only** (doc 4 §4).

---

## 9. Deep links

`bugcoffee://bean/<beanId>` opens that bean's page: switch to the Products tab and select the
bean. The host is `bean` and there is exactly **one** path component, the bean id (doc 3 §1.2).

- An unknown or retired bean id, or any other URL on the scheme, is **ignored** — the user
  stays where they are rather than landing on an empty page.
- The link is handled even while the login screen is up; the selection is stored above the tab
  UI so it applies as soon as the user is in.
- The bean page hands this link out through the system share sheet, with the bean name as the
  subject and its tasting notes as the message.

---

## 10. Group coffee order

One person starts a "coffee run" in a chat, picks drinks, and sends it; everyone else opens the
same message, adds their drinks, and sends it back — **the whole order lives inside the link**,
there is no server. On iOS this is an iMessage app that updates one bubble in place; elsewhere
it is a shared deep link (doc 4 §5). The wire format, pricing and aggregation rules are in
doc 6.

**Compact/entry state** — brand-dark, "☕️ Bug Coffee" plus either
"Start a group coffee order for this chat." or, when joining an existing order,
"There's a coffee run going — add your drinks!", and a capsule button reading
**"Start a coffee run"** / **"Add my order"**.

**Expanded state** — header "Bug Coffee — group order", then:

- **"Order so far"** — everyone else's lines as `"<qty>× <title>"`, labelled per participant.
  Absent when nobody else has ordered; then the menu is introduced with
  "Pick something from the menu below".
- **"Your drinks"** — your editable lines. Each: the line title, a **quantity stepper (1…9)**,
  a **"Decaf"** chip (only when the drink allows it), a **milk menu** ("Regular milk" plus each
  alternative milk with its surcharge, e.g. "Oat (+0.60 €)"), and — for coffee-based drinks —
  a **bean chip** menu listing "Find my blend…", "House blend", then every bean with its star
  rating appended. The line's own total shows on the right.
- **The full menu** — favorites first, each row with a **★ toggle** and a **+ add** button.
  Adding a drink that is already present as a *plain* line (no decaf, no alternative milk,
  house blend) just **increments its quantity**.
- **Submit bar** — "Your drinks" with your subtotal in dual currency, and a button reading
  **"Send order to the chat"** or **"Add my drinks to the order"**, disabled until you have at
  least one line.

**Participants** appear as **"You" / "Friend 1" / "Friend 2"…** — the reference platform never
exposes contact names to the extension, and the protocol carries only opaque ids (doc 6 §3).

**Submitting** replaces *your* lines in the order and leaves everyone else's untouched, then
hands the message to the user to send — the app never sends on their behalf.
