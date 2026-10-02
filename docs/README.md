# Bug Coffee — cross-platform porting documentation

This folder is the **specification of the Bug Coffee app as built on iOS**, written so the
same product can be rebuilt on another platform (Android, Wear OS, Flutter/KMP, web/PWA,
desktop) without reading Swift.

It describes **behavior, data, protocols and integrations** — not SwiftUI. Where an Apple
mechanism has no direct counterpart, the document names the equivalent capability and what
changes.

The iOS app in this repository is the **reference implementation**: when this documentation
and the code disagree, the code (`BugWallet/Sources`, `Shared`, `MessagesExtension`,
`StampWidget`, `BugWalletWatch`) is the source of truth. Every claim below has a file
reference so you can check it.

## The documents

| # | Document | What it answers |
|---|----------|-----------------|
| 1 | [Product behavior](01-product-behavior.md) | Every screen, control, state and user-visible string |
| 2 | [Backend, auth & the stamp count](02-backend-auth-and-stamps.md) | Firebase config, sign-in call, Firestore model, the App Check problem and the three ways around it |
| 3 | [Data & storage](03-data-and-storage.md) | The static menu/bean datasets, price rules, persisted keys, on-disk JSON schemas |
| 4 | [Platform mapping](04-platform-mapping.md) | iOS component → Android / Wear / web equivalent, per capability |
| 5 | [Loyalty pass](05-wallet-pass.md) | Apple Wallet pass contents and the Google Wallet loyalty-object mapping |
| 6 | [Group-order protocol](06-group-order-protocol.md) | The serverless order wire format (v3), pricing and aggregation rules |
| 7 | [Design & copy](07-design-and-copy.md) | Brand tokens, layout rules, the stamp-jitter algorithm, exact copy |
| 8 | [Build & verify](08-build-and-verify.md) | Building/running the iOS reference app, and the acceptance tests a port must pass |
| 9 | [Screenshots](09-screenshots.md) | What the reference app's screens look like, and how to regenerate the images |

## The product in six sentences

1. A customer logs in with their existing **Bug Coffee web account** (Firebase email/password).
2. The app shows a **QR code containing that account's Firebase UID** — that string, verbatim,
   is what the barista scans. Everything else is extra.
3. A **9-slot stamp card** mirrors the paper loyalty card: read from the backend when that is
   possible, otherwise maintained by the user with +/− (see doc 2).
4. A **static menu** (drinks + whole-bean bags) with favorites, a per-bean **tasting diary**,
   and a **"find my blend" quiz** that scores the shop's taste profiles against the user's own
   ratings.
5. Side surfaces: **platform wallet pass**, **home-screen widget**, **watch app**, **caffeine
   logging to the system health store**, a **serverless group order** shared into a chat, and
   **deep links** to a bean page.
6. There is **no Bug Coffee server of our own**: the only network calls are Firebase
   sign-in and (conditionally) one Firestore document read.

## Porting order

Build it in this order; each step is independently shippable.

| Milestone | Scope | Docs |
|-----------|-------|------|
| **M1 — core** | Sign-in, session restore, sign-out, loyalty QR, copyable UID | 1 §2–3, 2 §1–3, 7 |
| **M2 — stamps** | 9-slot card, manual +/−, shared storage | 1 §4, 2 §5, 3 §3, 7 §4 |
| **M3 — products** | Static menu, favorites, bean pages, tasting diary, blend quiz | 1 §5–6, 3 §1–2, 3 §4 |
| **M4 — companions** | Widget, watch app, deep links | 1 §7–9, 3 §3, 4 |
| **M5 — integrations** | Health/caffeine logging, wallet pass | 1 §6.1, 4, 5 |
| **M6 — social** | Group order via share link | 1 §10, 6 |
| **M7 — optional** | Live stamp count (needs a decision — read doc 2 §5 first) | 2 §5 |

M1 + M2 is the whole product for most users. M7 is the one item with a real external
dependency and a policy decision attached.

## Non-goals — keep them on every platform

These are deliberate and should not be "fixed" during a port:

- **No sign-up, password reset or social login.** Accounts come from the shop's web app.
- **No menu or ordering backend.** The menu is a static dataset (doc 3 §1); a group order is
  peer-to-peer through a link and is never submitted to the shop. No payments.
- **No push notifications, no analytics, no tracking, no in-app purchases, no ads.**
- **No device fingerprinting.** The backend field is *called* `fingerprint`, but its value is
  always the UID (doc 2 §4).
- **No attempt to read another user's data.** Every read is the signed-in user's own document.
