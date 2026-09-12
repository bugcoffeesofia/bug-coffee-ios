# 7 — Design, layout and copy

Reference: `Shared/StampCard.swift` (brand + stamp card), each `*View.swift`,
`MessagesExtension/Sources/OrderViews.swift`.

---

## 1. Brand tokens

| Token | Hex | RGB | Where |
|-------|-----|-----|-------|
| Brand dark brown | `#1F0409` | 31, 4, 9 | Screen backgrounds, widget background, pass background, order card |
| Accent red | `#CC1E41` | 204, 30, 65 | Buttons, counters, stamps, tasting notes, stars, pass label color |
| Cream | `#F6EEE3` | 246, 238, 227 | Empty stamp outlines (at **35 % opacity**) |
| Foreground | `#FFFFFF` | — | Text on brand dark |

Opacity ladder used on dark backgrounds — keep it, it carries the hierarchy:
**1.0** primary text · **0.8** captions under the QR, result lines · **0.7** the email under the
wordmark, widget status line · **0.5** the backend diagnostics line · **0.4** the UID footer.

Type: the wordmark is **rounded, bold** (34pt on login, title2 in the card header). Counters and
the UID use **monospaced digits / monospaced**. Everything else is the platform's system font at
semantic sizes.

Shapes: 12pt corner radius for buttons and the login field card, **20pt** for the white QR card,
14pt for the group-order submit button, capsules for chips and the quiz's pick button.

---

## 2. Layout rules that matter

- **Cap content width at ~440pt** on wide displays (login form, the card's controls column).
  Full-width text fields and rows on a large screen read badly.
- **Scroll instead of clipping.** The login and card screens lay out at least as tall as the
  viewport and scroll when they don't fit (keyboard, split view, largest text sizes). Bounce
  only when scrolling is actually needed.
- **Modals belong to the screen root**, not to a section, so they survive a size-class change
  mid-presentation (a foldable opening, a rotation).
- On a **regular-width** display the card splits into halves — QR on one side, stamps + actions
  on the other; side by side when wider than tall, stacked when taller than wide. The Products
  tab becomes a two-column list/detail split.
- **QR rendering: nearest-neighbour, never smoothed** (on every surface — card, watch, preview).
  A blurred QR scans badly.
- Toolbar items carry **both a title and a symbol**, so they degrade into an overflow menu with
  readable labels. Where priorities exist: the favorite star (which shows state) survives
  longer than Share; a sheet's Save is the pinned main action after Cancel.

---

## 3. Accessibility

- The favorite star's label reads "Add <name> to favorites" / "Remove <name> from favorites".
- Star ratings expose "<n> out of 5", and the bean row's average reads "your average 3.8 out
  of 5" — the glyph string alone is not readable.
- The scan-and-share button is labelled "Scan and share a pass".
- The UID footer is **selectable text** (copy support), not an image.
- Nothing in the app depends on color alone: a filled stamp differs from an empty one in glyph
  *and* outline style, and the free-drink state has its own text line.

---

## 4. The stamp card

- A **3×3 grid** of circular slots, filled left-to-right, top-to-bottom for index < count.
- **Empty slot**: a dashed circle outline — 1.5pt line, dash pattern `[4, 3]`, cream at 35 %.
- **Filled slot**: an accent ring of `slotSize × 0.07` plus a filled cup glyph at
  `slotSize × 0.4`, bold, accent, the whole stamp at **92 % opacity**.
- Sizes in use: **34pt** slots / 8pt spacing (card, watch, medium widget), **30pt** / 7pt
  (small widget), 40pt/10pt default.

### 4.1 Deterministic jitter (port this exactly)

Collected stamps sit slightly off-center and rotated, like real ink on paper. The offset is
**seeded by the slot index**, so the card renders identically every time — otherwise stamps
visibly jump between widget refreshes and between surfaces.

```
state = (slot + 1) × 0x9E3779B97F4A7C15        // 64-bit, wrapping

unit():                                         // splitmix64 → [0, 1)
    state += 0x9E3779B97F4A7C15                 // wrapping
    z = state
    z = (z XOR (z >> 30)) × 0xBF58476D1CE4E5B9  // wrapping
    z = (z XOR (z >> 27)) × 0x94D049BB133111EB  // wrapping
    return ((z XOR (z >> 31)) >> 11) / 2^53

rotationDegrees = (unit() − 0.5) × 40           // ±20°
dx              =  unit() − 0.5                 // then × slotSize × 0.24  → ±12 %
dy              =  unit() − 0.5                 // then × slotSize × 0.24
```

All arithmetic is **unsigned 64-bit with wrapping** (`&*`, `&+` in Swift; `ULong` in Kotlin is
wrapping by default; in JS use `BigInt` masked to 64 bits). Draw order matters: rotation first,
then dx, then dy.

---

## 5. Copy inventory

Every user-visible string, for translation or verification. `<…>` are substitutions.

**Login** — "Bug Coffee" · "Sign in to show your loyalty card" · "Email" · "Password" ·
"Sign In"

**Auth errors** — "Wrong email or password." · "This account has been disabled." ·
"Too many attempts. Please try again later." · "Unexpected response from the server."

**Card** — "Bug Coffee" · "Sign out" · "Show this to the barista" · "Stamps" · "<n> / 9" ·
"Backend: <status>" · "UID: <uid>"

**Health** — "Log a coffee" · "Logging…" · "<Drink> · <n> mg" · "<Drink> logged to Health ☕️" ·
"Health data isn't available on this device." · "Health access is off. Enable Caffeine in
Settings → Health → Data Access."

**Wallet (optional)** — "In Apple Wallet" · "Scan and share a pass" · "Name for the pass" ·
"This name will appear on the shared Wallet pass." · "Create pass" · "Cancel" ·
"Couldn't build pass: <error>" · "That QR didn't contain a UID." · "Wallet couldn't open this
pass." · "Invalid pass: <error>" · "Camera access denied." · "Camera access denied. Enable it in
Settings to scan."

**Products** — "Products" · "Drinks" · "Coffee beans" · "Find my blend" ·
"Pick a bean to see its tasting notes and your diary." · "<size> · <€> / <лв.>" · "· ★ <avg>" ·
"Add to favorites" · "Remove from favorites"

**Bean page** — "Your average" · "<n> cups" · "<n> cups · <m> rated" · "Diary" · "Add a cup" ·
"Grind: <text>"

**Cup editor** — "How was it?" · "The cup" · "Made as" · "Espresso bar" · "Brewed" · "Where" ·
"When" · "Notes" · `Grind size ("18 clicks", "medium-fine"…)` ·
`What did you think? ("syrupy", "sour — grind finer"…)` · "Grind is worth noting when you ground
the beans yourself." · "Cancel" · "Save"

**Quiz** — "Find my blend" · "How do you drink it?" · "Serving" · "Black" · "With milk" ·
"Caffeine" · "Regular" · "Decaf" · "Which direction?" · "Chocolate & nuts" · "Fruity & bright" ·
"Surprise me" · "Your matches" · "Add to favorites" · "Use this blend" · "Close"

**Widget** — "Stamp Card" · "Your Bug Coffee stamps at a glance." · "Bug Coffee" ·
"Free drink earned! 🎉" · "<n> to a free drink"

**Watch** — "Bug Coffee" · "Loyalty card" · "Stamps" · "Log caffeine" · "Find my blend" ·
"Card" · "Sign in on your iPhone to show your loyalty card" · "Free drink ready! 🎉" ·
"<n> to go for a free drink"

**Group order** — "☕️ Bug Coffee" · "Start a group coffee order for this chat." ·
"There's a coffee run going — add your drinks!" · "Start a coffee run" · "Add my order" ·
"Bug Coffee — group order" · "Order so far" · "Pick something from the menu below" ·
"Your drinks" · "Decaf" · "Regular milk" · "<Milk> (+0.60 €)" · "House blend" ·
"Find my blend…" · "Send order to the chat" · "Add my drinks to the order" ·
"Bug Coffee group order" · "<n> drinks · <m> people · <total> €" · "+ <n> more…" · "You" ·
"Friend <n>" · "<qty>× <title>"

**Permission prompts** (adapt per platform, keep the meaning):

- Camera — "Bug Coffee uses the camera to scan a loyalty QR so it can create a Wallet pass to
  share."
- Health write — "Bug Coffee saves the caffeine from coffees you log to Apple Health."
- Health read — "Bug Coffee reads nothing from Health; access is only used to confirm your
  caffeine logging permission."

### 5.1 Localization state

The app's UI is **English**, with Bulgarian kept where it is the shop's own vocabulary: serving
sizes ("220 мл", "250 г"), the wallet pass field labels ("ПЕЧАТИ", "ЧЛЕН"), the pass's nearby
text ("Bug Coffee е наблизо"), and the лв. side of every price. Nothing is run through a
localization system yet — a port that adds one should keep those strings as the Bulgarian
locale's values rather than translating them away.
