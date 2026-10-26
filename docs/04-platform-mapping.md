# 4 — Platform mapping

What each iOS mechanism is doing, and what to use instead. The **capability** is the
requirement; the API is negotiable.

---

## 1. Component map

| iOS component | Type | Purpose | Android | Other targets |
|---------------|------|---------|---------|---------------|
| **BugCoffee** | app | Login, card, products, stamps, health log | app | the whole product |
| **BugCoffeeStampWidget** | WidgetKit extension | Stamp card at a glance | App Widget (Jetpack Glance / RemoteViews) | web: none (or a PWA badge); desktop: tray/menu-bar item |
| **BugCoffeeWatch** | watchOS app | QR, stamps, caffeine log, blend quiz | Wear OS app | — |
| **BugCoffeeMessages** | iMessage extension | Group order inside a chat | share-sheet deep link (no equivalent exists) | web: a shareable URL |
| **Apple Wallet pass** | signed `.pkpass` | Card in the platform wallet | Google Wallet loyalty object | — (doc 5) |
| **`make_pkpass.sh`** | shell script | Signs a pass on a Mac | not needed | — |

Shared code (`Shared/`) is deliberately dependency-free data + scoring: menu, bean profiles,
quiz scoring, diary model, stamp-card view, storage keys. **Mirror that split** — one module
with no platform imports, consumed by app, widget and watch. On Android that is a plain Kotlin
module (or KMP `commonMain`); it is what makes the quiz score identically on phone and watch.

---

## 2. Capability map

| Capability | iOS | Android | Notes for a port |
|------------|-----|---------|------------------|
| Sign-in | Identity Toolkit REST (`URLSession`) | Firebase Auth SDK, or the same REST call | SDK gives you token refresh; REST keeps you dependency-free (doc 2 §2) |
| QR rendering | Core Image `CIQRCodeGenerator`, level **H** | ZXing / `zxing-android-embedded`, ECC level H | Nearest-neighbour scaling, no smoothing |
| QR scanning (optional) | AVFoundation metadata output | CameraX + ML Kit barcode / ZXing | Only for the scan-and-share pass flow |
| Shared storage | App Group `UserDefaults` | DataStore in a shared module, or a ContentProvider for a separate widget process | doc 3 §3 |
| Secure storage | (reference uses plain prefs) | EncryptedSharedPreferences / Keystore | Refresh token belongs here |
| Widget | WidgetKit static timeline + explicit reload | Glance `GlanceAppWidget` + `updateAll()` | The count changes only from the app, so no periodic refresh |
| Watch sync | WatchConnectivity `updateApplicationContext` | Wearable **Data Layer** (`DataClient`) | §4 |
| Health write | HealthKit dietary caffeine | **Health Connect** caffeine record (Google Fit is deprecated) | Write-only permission, same six drinks |
| Platform wallet | PassKit `.pkpass` | Google Wallet loyalty object (JWT "Save" flow) | doc 5 |
| Deep links | custom URL scheme | intent filter for `bugcoffee://bean/<id>`, plus an App Link if you have a domain | doc 1 §9 |
| Share a file/link | `UIActivityViewController` | `ACTION_SEND` chooser | — |
| Embedded web (Option C) | `WKWebView` + user scripts | `WebView` + `evaluateJavascript`/`WebViewClient`, JS bridge | doc 2 §5.3 |
| Group order | iMessage app | share sheet + deep link | doc 6 §5 |

---

## 3. Widget

The count only changes when the app writes it, so:

- No periodic refresh, no network from the widget, no timeline schedule (iOS uses a single
  never-expiring entry).
- The **app** requests the refresh after each write.
- Two sizes with distinct layouts (doc 1 §7); pick the closest equivalent size buckets and keep
  both layouts.
- Placeholder/preview state shows **4** stamps.

---

## 4. Watch sync

The iOS design is **phone → watch, one-way, latest-value-wins**:

- Payload keys `uid`, `email`, `qr` (PNG bytes), `stamps` (int).
- `updateApplicationContext` replaces the whole payload on each call, so the sender keeps the
  last dictionary and **merges partial updates** (e.g. a new stamp count) before resending —
  otherwise a stamp push would erase the uid and QR.
- It is queued and delivered even when the watch app is closed or the watch is asleep, which
  suits a rarely-changing identity.
- The watch **persists** what it receives and reads it back at launch, so it works standalone.
- The phone **re-pushes on every launch**, so a returning user's watch stays in sync without a
  fresh login.
- On activation, the receiver also reads whatever context arrived while it was closed.

Porting notes:

- The Wearable **Data Layer** has the same semantics (`DataClient` items are latest-value,
  synced when the peer is available). Mirror the merge rule.
- **Wear OS can generate a QR itself**, so send just the UID string and render on the watch —
  the PNG shuttle exists only because Core Image is unavailable on watchOS. Keep persisting
  the last value.
- Keep stamps **read-only on the watch**: the count's real source is the backend or the phone's
  manual tracker, and a two-way editable counter invites conflicts.

---

## 5. Group order without a message extension

No other platform has an in-conversation extension, and the protocol was designed for that
(doc 6). Recreate it as a **shareable deep link**:

1. Build the same `?v=3&o=…` URL.
2. Share it with the system share sheet, into any chat app.
3. Register an intent filter / App Link so tapping it opens the order editor pre-filled from
   the link.
4. Sending the updated order = building a new link and sharing it back into the same chat.

Two consequences to handle:

- **No conversation identity.** iMessage supplies a stable per-conversation participant id;
  elsewhere you must **generate and persist a per-install UUID** and use it as the participant
  id. Same shape, same "You / Friend N" labels.
- **No in-place update.** Each share is a new message rather than one bubble updating, so the
  thread will show the order's history. Acceptable; make the summary line good enough to read
  at a glance.

For the message preview, a rendered card image (doc 6 §4) still helps where the chat app shows
link previews; otherwise rely on the link's text summary.

---

## 6. Web / PWA notes

The shop already has a web app, so a new web client is mostly redundant — but if you build one:

- Auth, QR and the live stamp count all work in a browser (that is the one environment where
  App Check is satisfied natively — doc 2 §5).
- The static menu, favorites, diary and quiz port directly; use `localStorage`/IndexedDB for the
  storage keys in doc 3 §3.
- No widget, no watch, no health store; the wallet pass becomes an "Add to Google/Apple Wallet"
  server-side flow.

## 7. Flutter / KMP notes

- The whole of `Shared/` maps to `commonMain` (or plain Dart): data, scoring, diary model,
  price formatting, link encoding/decoding. That is the bulk of the porting value.
- Platform channels are still needed for: health store, platform wallet, widget, watch, and the
  embedded WebView (Option C).
- Keep the **stamp jitter algorithm** (doc 7 §4) in shared code — it must produce identical
  output on every surface, or the card visibly "jumps" between app, widget and watch.
